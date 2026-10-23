import CoreLocation
import Observation
import SwiftData

// Core Location delivers callbacks on the run loop where the manager was created (main).
@MainActor @Observable final class WeatherService: NSObject, @preconcurrency CLLocationManagerDelegate {
    var enabled = UserDefaults.standard.object(forKey:"localWeatherEnabled") as? Bool ?? true {
        didSet {
            guard enabled != oldValue else { return }
            UserDefaults.standard.set(enabled,forKey:"localWeatherEnabled"); scopeRevision += 1
            if enabled { startRefresh(allowPrompt:true,force:true) }
            else { work?.cancel(); finishLocation(.failure(WeatherFailure.disabled)); error = nil }
        }
    }
    private(set) var forecast: WeatherForecast?
    private(set) var loading = false
    private(set) var error: String?
    private(set) var authorization = CLAuthorizationStatus.notDetermined
    private(set) var scopeRevision = 0
    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var container: ModelContainer?
    @ObservationIgnored private var locationWait: CheckedContinuation<CLLocation,Error>?
    @ObservationIgnored private var timeout: Task<Void,Never>?
    @ObservationIgnored private var work: Task<Void,Never>?
    @ObservationIgnored private var lastAttempt = Date.distantPast
    // macOS reports its single authorised state using this legacy enum case.
    // We only request when-in-use access and stop updates after one fix.
    var allowed: Bool { authorization == .authorizedAlways }
    var scope: String { "\(enabled):\(authorization.rawValue):\(scopeRevision)" }
    var status: String {
        if !enabled { return "Local weather is off" }
        if loading { return "Getting your nearby forecast…" }
        if let error { return error }
        if let forecast {
            if !forecast.usable() { return "Previous forecast is out of date · Refresh to update" }
            return "\(Date.now.timeIntervalSince(forecast.fetched) > 1800 ? "Cached" : "Updated") \(forecast.fetched.formatted(date:.omitted,time:.shortened)) · Nearby area"
        }
        return allowed ? "Forecast not yet available" : authorization == .notDetermined ? "Location permission has not been requested" : WeatherFailure.denied.localizedDescription
    }
    init(container: ModelContainer?) {
        self.container = container
        super.init()
        manager.delegate = self; manager.desiredAccuracy = kCLLocationAccuracyKilometer
        authorization = manager.authorizationStatus
        if let container {
            forecast = try? LocalRecordRepository(container: container).decode("localWeather", as: WeatherForecast.self)
        }
    }
    func startRefresh(allowPrompt: Bool = false, force: Bool = false) {
        guard enabled, !loading, force || Date.now.timeIntervalSince(lastAttempt) >= 1800 else { return }
        guard allowed || (allowPrompt && authorization == .notDetermined) else { return }
        work = Task { await refresh(allowPrompt:allowPrompt) }
    }
    func prepareForBrief() async {
        // The scheduled brief never asks for a new OS permission or performs inference.
        guard enabled, allowed else { return }
        startRefresh()
        await work?.value
    }
    private func refresh(allowPrompt: Bool) async {
        guard enabled, !loading else { return }
        loading = true; lastAttempt = .now; error = nil
        defer { loading = false }
        do {
            let fix = try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CLLocation,Error>) in
                    locationWait = continuation
                    timeout = Task { try? await Task.sleep(for:.seconds(30)); guard !Task.isCancelled else { return }; finishLocation(.failure(WeatherFailure.timeout)) }
                    if allowed { manager.startUpdatingLocation() }
                    else if allowPrompt && authorization == .notDetermined {
                        manager.requestWhenInUseAuthorization()
                        // Native macOS also initiates its permission alert when the service starts.
                        manager.startUpdatingLocation()
                    }
                    else { finishLocation(.failure(WeatherFailure.denied)) }
                }
            } onCancel: { Task { @MainActor [weak self] in self?.finishLocation(.failure(CancellationError())) } }
            try Task.checkCancellation()
            let captured = scope, timezone = TimeZone.current
            var request = URLRequest(url:try WeatherRules.url(latitude:fix.coordinate.latitude,longitude:fix.coordinate.longitude,timezone:timezone)); request.timeoutInterval = 15
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 15; configuration.timeoutIntervalForResource = 20
            let session = URLSession(configuration:configuration)
            defer { session.invalidateAndCancel() }
            let (data,response) = try await session.data(for:request)
            try Task.checkCancellation()
            guard enabled, allowed, captured == scope else { return }
            guard let response = response as? HTTPURLResponse, response.statusCode == 200, data.count < 100_000 else { throw WeatherFailure.unavailable }
            let result = try WeatherRules.decode(data,timezone:timezone)
            forecast = result
            if let container {
                do { try LocalRecordRepository(container: container).save(result, key: "localWeather") } catch { self.error = "Forecast loaded, but could not be saved for relaunch." }
            }
        } catch is CancellationError { }
        catch { if enabled { self.error = (error as? WeatherFailure)?.localizedDescription ?? WeatherFailure.unavailable.localizedDescription } }
    }
    private func finishLocation(_ result: Result<CLLocation,Error>) {
        manager.stopUpdatingLocation(); timeout?.cancel(); timeout = nil
        let continuation = locationWait; locationWait = nil; continuation?.resume(with:result)
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let changed = authorization != manager.authorizationStatus
        if changed { authorization = manager.authorizationStatus; scopeRevision += 1 }
        if locationWait != nil {
            if allowed { manager.startUpdatingLocation() }
            else if authorization != .notDetermined { finishLocation(.failure(WeatherFailure.denied)) }
        } else if changed && allowed && enabled { startRefresh(force:true) }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let fix = locations.last, fix.horizontalAccuracy >= 0, fix.horizontalAccuracy <= 20_000, abs(fix.timestamp.timeIntervalSinceNow) < 120 else { return }
        finishLocation(.success(fix))
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if (error as? CLError)?.code == .locationUnknown { return }
        finishLocation(.failure((error as? CLError)?.code == .denied ? WeatherFailure.denied : WeatherFailure.unavailable))
    }
    func context(now: Date = .now) -> [String:Any] {
        guard enabled, allowed else { return ["status":"Local weather disabled or location not authorised. No forecast supplied."] }
        guard let forecast, forecast.usable(now:now) else { return ["status":"No recent local forecast is available."] }
        return ["status":error != nil || now.timeIntervalSince(forecast.fetched) > 1800 ? "Cached forecast; may be stale" : "Recent forecast", "provider":"Open-Meteo", "area":"Nearby approximate area", "fetched":forecast.fetched.ISO8601Format(), "timezone":forecast.timezone, "units":"Celsius, rain probability percent, maximum wind km/h", "days":forecast.days.map { ["date":$0.date,"conditions":$0.description,"low":$0.low,"high":$0.high,"rainChance":$0.rainChance,"maximumWind":$0.windKmh] as [String:Any] }]
    }
}
