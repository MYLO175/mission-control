import Foundation
import CoreGraphics

/// Stable bilateral hubs keep labels clear while the widget continuously resizes.
struct LifeMapLayout {
    let width:CGFloat
    let count:Int
    var dense=false
    var rootSize:CGFloat { dense ? 64 : 88 }
    var cardHeight:CGFloat { dense ? 56 : 72 }
    var rowSpacing:CGFloat { dense ? 76 : 100 }
    var compact:Bool { !dense && width < 360 }
    var cardWidth:CGFloat { compact ? max(80,width-46) : min(dense ? 180 : 190,(width-(dense ? 100 : 112))/2) }
    var height:CGFloat { compact ? CGFloat(100+count*92) : max(dense ? 220 : 280,CGFloat((count+1)/2)*rowSpacing+40) }
    var root:CGPoint { CGPoint(x:width/2,y:compact ? 48 : height/2) }
    func card(_ index:Int)->CGRect {
        if compact { return CGRect(x:38,y:CGFloat(100+index*92),width:cardWidth,height:72) }
        let side=index%2,rows=(count+1-side)/2
        let y=(height-CGFloat(rows-1)*rowSpacing)/2+CGFloat(index/2)*rowSpacing
        return CGRect(x:side == 0 ? 4 : width-cardWidth-4,y:y-cardHeight/2,width:cardWidth,height:cardHeight)
    }
    func branch(_ index:Int)->(start:CGPoint,end:CGPoint,control1:CGPoint,control2:CGPoint) {
        let rect=card(index)
        if compact {
            let start=CGPoint(x:18,y:rect.midY),end=CGPoint(x:rect.minX,y:rect.midY)
            return (start,end,start,end)
        }
        let left=index%2 == 0
        let start=CGPoint(x:root.x+(left ? -rootSize/2 : rootSize/2),y:root.y),end=CGPoint(x:left ? rect.maxX : rect.minX,y:rect.midY)
        let x=(start.x+end.x)/2
        return (start,end,CGPoint(x:x,y:start.y),CGPoint(x:x,y:end.y))
    }
}

/// A capped intrinsic canvas is uniformly scaled and centred, never clipped or stretched.
struct LifeMapFit {
    let available:CGSize
    let count:Int
    var layout:LifeMapLayout { LifeMapLayout(width:max(480,min(760,available.width)),count:count,dense:true) }
    var scale:CGFloat { max(0,min(1,min(available.width/layout.width,available.height/layout.height))) }
    var origin:CGPoint { CGPoint(x:(available.width-layout.width*scale)/2,y:(available.height-layout.height*scale)/2) }
}
