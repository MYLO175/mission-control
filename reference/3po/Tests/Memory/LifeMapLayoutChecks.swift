import Foundation
import CoreGraphics
@main struct Checks {
    static func main() {
        for width:CGFloat in [180,280,359,360,440,680,1200] {
            for count in 1...10 {
                let layout=LifeMapLayout(width:width,count:count)
                let bounds=CGRect(x:0,y:0,width:width,height:layout.height)
                let root=CGRect(x:layout.root.x-44,y:layout.root.y-44,width:88,height:88)
                precondition(bounds.contains(root))
                let cards=(0..<count).map(layout.card)
                for (i,card) in cards.enumerated() {
                    precondition(bounds.contains(card),"Labels stay inside the widget")
                    precondition(!card.intersects(root),"Area labels do not overlap the owner")
                    for j in cards.indices where i != j { precondition(!card.intersects(cards[j])) }
                    let branch=layout.branch(i)
                    precondition(branch.end.x == card.minX || branch.end.x == card.maxX,"Branches end at label edges")
                }
            }
        }
        for width:CGFloat in [180,280,320,440,680,1200,1800] {
            for height:CGFloat in [100,180,280,420,800] {
                for count in 1...10 {
                    let fit=LifeMapFit(available:CGSize(width:width,height:height),count:count),layout=fit.layout
                    let bounds=CGRect(x:0,y:0,width:width,height:height)
                    let canvas=CGRect(origin:fit.origin,size:CGSize(width:layout.width*fit.scale,height:layout.height*fit.scale))
                    precondition(bounds.insetBy(dx:-0.001,dy:-0.001).contains(canvas),"Entire fitted map stays visible")
                    precondition(fit.scale > 0 && fit.scale <= 1 && !layout.compact)
                    let root=CGRect(x:layout.root.x-layout.rootSize/2,y:layout.root.y-layout.rootSize/2,width:layout.rootSize,height:layout.rootSize)
                    let cards=(0..<count).map(layout.card)
                    for (i,card) in cards.enumerated() {
                        precondition(!card.intersects(root))
                        for j in cards.indices where i != j { precondition(!card.intersects(cards[j])) }
                    }
                }
            }
        }
        precondition(PAIdentity.name(nil) == "Your PA")
        precondition(PAIdentity.validated("  3PO  ") == "3PO")
        precondition(PAIdentity.validated("Name\nInstruction") == nil)
        precondition(PAIdentity.validated(String(repeating:"a",count:41)) == nil)
        precondition(PAIdentity.placeholder("3PO") == "Message 3PO")
        precondition(PAIdentity.context("Name \"quoted\"").contains("\\\"quoted\\\""))
        print("PASS: 350 fitted size/count combinations plus 70 narrow/wide map layouts, edge branches, name validation and escaped identity context")
    }
}
