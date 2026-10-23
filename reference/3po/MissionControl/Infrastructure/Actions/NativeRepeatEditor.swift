import SwiftUI

struct NativeRepeatEditor: View {
    @Binding var rules: [NativeRecurrence]
    @State private var identities: [UUID] = []
    var body: some View {
        VStack(alignment:.leading,spacing:10) {
            HStack { Text("Repeat").font(.subheadline.weight(.semibold)); Spacer(); Button("Add repeat rule") { rules.append(.init());identities.append(UUID()) }.disabled(rules.count >= 8) }
            if rules.isEmpty { Text("Never").foregroundStyle(.secondary) }
            ForEach(Array(zip(identities,rules.indices)),id:\.0) { _,index in
                VStack(alignment:.leading,spacing:10) {
                    NativeRepeatRuleEditor(rule:$rules[index])
                    Button("Remove repeat rule",role:.destructive) { rules.remove(at:index);identities.remove(at:index) }
                }.padding(10).background(Color.primary.opacity(0.04),in:RoundedRectangle(cornerRadius:8))
            }
        }.onAppear { identities=rules.map{_ in UUID()} }
    }
}
private struct NativeRepeatRuleEditor: View {
    @Binding var rule: NativeRecurrence
    @State private var endMode = "forever"
    @Environment(\.timeZone) private var timeZone
    private var calendar:Calendar {var value=Calendar.current;value.timeZone=timeZone;return value}
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            HStack {
                Picker("Every",selection:$rule.frequency) { Text("Day").tag("daily");Text("Week").tag("weekly");Text("Month").tag("monthly");Text("Year").tag("yearly") }
                    .onChange(of:rule.frequency) { rule.weekdays=[];rule.monthDays=[];rule.months=[];rule.yearWeeks=[];rule.yearDays=[];rule.positions=[] }
                Stepper("Interval: \(rule.interval)",value:$rule.interval,in:1...999)
            }
            if rule.frequency == "weekly" {
                HStack(spacing:6) {
                    ForEach(1...7,id:\.self) { day in
                        Toggle(Calendar.current.shortWeekdaySymbols[day-1],isOn:Binding(get:{ rule.weekdays.contains(where:{$0.weekday == day}) },set:{ on in rule.weekdays.removeAll{$0.weekday == day};if on {rule.weekdays.append(.init(weekday:day));rule.weekdays.sort{$0.weekday < $1.weekday}} })).toggleStyle(.button)
                    }
                }
            }
            if rule.frequency == "weekly" && rule.weekdays.isEmpty {Text("Uses the event start day or reminder due day.").font(.caption).foregroundStyle(.secondary)}
            if rule.frequency == "monthly" { NativeIntegerList(label:"Days of month",values:$rule.monthDays,hint:"1–31; -1 is the last day. Leave empty to use the start day.") }
            if rule.frequency == "yearly" { NativeIntegerList(label:"Months",values:$rule.months,hint:"1–12; comma separated. Empty uses the start month.") }
            if rule.frequency == "monthly" || rule.frequency == "yearly" {
                DisclosureGroup("Advanced repeat pattern") {
                    NativeWeekdayList(values:$rule.weekdays)
                    if rule.frequency == "yearly" {
                        NativeIntegerList(label:"Weeks of year",values:$rule.yearWeeks,hint:"1–53 or negative from year end")
                        NativeIntegerList(label:"Days of year",values:$rule.yearDays,hint:"1–366 or negative from year end")
                    }
                    NativeIntegerList(label:"Positions in matching dates",values:$rule.positions,hint:"For example -1 chooses the last match.")
                }
            }
            Picker("Ends",selection:$endMode) { Text("Never").tag("forever");Text("On date").tag("date");Text("After occurrences").tag("count") }
                .onChange(of:endMode) { mode in rule.endDate = mode == "date" ? (rule.endDate ?? calendar.date(bySettingHour:23,minute:59,second:59,of:.now)!) : nil;rule.count = mode == "count" ? max(1,rule.count) : 0 }
            if endMode == "date" { DatePicker("Last repeat date",selection:Binding(get:{rule.endDate ?? .now},set:{rule.endDate=calendar.date(bySettingHour:23,minute:59,second:59,of:$0)}),displayedComponents:.date) }
            if endMode == "count" { Stepper("\(rule.count) occurrences",value:$rule.count,in:1...100_000) }
        }.onAppear { endMode = rule.count > 0 ? "count" : rule.endDate != nil ? "date" : "forever" }
    }
}
private struct NativeIntegerList: View {
    var label: String
    @Binding var values: [Int]
    var hint: String
    @State private var text = ""
    var body: some View {
        VStack(alignment:.leading,spacing:3) {
            TextField(label,text:$text).textFieldStyle(.roundedBorder).onChange(of:text) {
                let parts=text.split(separator:",",omittingEmptySubsequences:false).map{String($0).trimmingCharacters(in:.whitespaces)}
                values = text.trimmingCharacters(in:.whitespaces).isEmpty ? [] : parts.map{Int($0) ?? 999_999}
            }
            Text(hint).font(.caption).foregroundStyle(.secondary)
        }.onAppear { text=values.map(String.init).joined(separator:", ") }
    }
}
private struct NativeWeekdayList: View {
    @Binding var values: [NativeRepeatDay]
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            HStack { Text("Weekdays");Spacer();Button("Add weekday") {values.append(.init(weekday:2,week:1))} }
            ForEach(values.indices,id:\.self) { index in
                HStack {
                    Picker("Which",selection:$values[index].week) {
                        Text("Every").tag(0);Text("First").tag(1);Text("Second").tag(2);Text("Third").tag(3);Text("Fourth").tag(4);Text("Fifth").tag(5);Text("Last").tag(-1)
                        if ![-1,0,1,2,3,4,5].contains(values[index].week) {Text("Number \(values[index].week)").tag(values[index].week)}
                    }
                    Picker("Day",selection:$values[index].weekday) {ForEach(1...7,id:\.self) {day in Text(Calendar.current.weekdaySymbols[day-1]).tag(day)}}
                    Button("Remove") {values.remove(at:index)}
                }
            }
        }
    }
}
