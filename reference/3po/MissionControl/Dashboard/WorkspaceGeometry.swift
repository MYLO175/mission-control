import Foundation
import CoreGraphics

/// The saved grid is independent of window size. Pointer deltas use a fixed canvas coordinate space.
struct WorkspaceGeometry {
    var width: Double
    var height: Double
    var rows: Int
    var gap: Double { min(12,max(0,width)/48,max(0,height)/Double(max(1,rows)*4)) }
    var column: Double { max(1,(width-gap*11)/12) }
    var row: Double { max(1,(height-gap*Double(rows-1))/Double(max(1,rows))) }
    var xStep: Double { column+gap }
    var yStep: Double { row+gap }
    func frame(_ rect: GridRect) -> CGRect {
        CGRect(x:Double(rect.x)*xStep,y:Double(rect.y)*yStep,width:Double(rect.w)*xStep-gap,height:Double(rect.h)*yStep-gap)
    }
    func preview(origin: GridRect, dx: Double, dy: Double, resizing: Bool, minimumColumns: Int, minimumRows: Int) -> CGRect {
        var value = frame(origin)
        if resizing {
            value.size.width = max(Double(minimumColumns)*xStep-gap,min(width-value.minX,value.width+dx))
            value.size.height = max(Double(minimumRows)*yStep-gap,min(height-value.minY,value.height+dy))
        } else {
            value.origin.x = max(0,min(width-value.width,value.minX+dx))
            value.origin.y = max(0,min(height-value.height,value.minY+dy))
        }
        return value
    }
    func target(origin: GridRect, dx: Double, dy: Double, resizing: Bool, minimumColumns: Int, minimumRows: Int) -> GridRect {
        let value = preview(origin:origin,dx:dx,dy:dy,resizing:resizing,minimumColumns:minimumColumns,minimumRows:minimumRows)
        if resizing {
            return GridRect(x:origin.x,y:origin.y,w:max(minimumColumns,min(12-origin.x,Int(((value.width+gap)/xStep).rounded()))),h:max(minimumRows,min(rows-origin.y,Int(((value.height+gap)/yStep).rounded()))))
        }
        return GridRect(x:max(0,min(12-origin.w,Int((value.minX/xStep).rounded()))),y:max(0,min(rows-origin.h,Int((value.minY/yStep).rounded()))),w:origin.w,h:origin.h)
    }
}

/// Allocate the remaining page height across note rows. A crowded page keeps a
/// readable preview; measuring the content above Notes makes scrolling irrelevant.
enum ProjectNotesLayout {
    static let spacing:CGFloat=14
    static func minimumWidth(_ width:CGFloat)->CGFloat {min(240,max(100,width))}
    static func previewHeight(availableHeight:CGFloat,width:CGFloat,count:Int)->CGFloat {
        let columns=max(1,Int((max(0,width)+spacing)/(minimumWidth(width)+spacing)))
        let rows=max(1,Int(ceil(Double(count)/Double(columns))))
        // Notes heading/top padding: 48. Card padding, options and gap: 60.
        return max(96,(availableHeight-48-spacing*CGFloat(rows-1))/CGFloat(rows)-60)
    }
}
