import SwiftUI
import WorkoutUI

/// Public-domain E.H. Shepard plates from *Winnie-the-Pooh* (1926), shipped as template images in
/// `Assets.xcassets/Illustrations` and tinted ink so they sit with the type. Raw values are the book page numbers.
enum Plate: String {
    case doormat = "shepard-10"             // Pooh on the doormat
    case bumpingDownstairs = "shepard-126"  // Christopher Robin dragging Pooh down the stairs
    case sittingTogether = "shepard-07"     // Christopher Robin and Pooh sitting, backs to us
    case balloonBoy = "shepard-26"          // Christopher Robin holding the balloon
    case walkingOff = "shepard-53"          // Pooh and Piglet walking away
    case tracking = "shepard-50"            // Pooh and Piglet following footprints
    case footprints = "shepard-33-1"        // a trail of footprints
    case poohStanding = "shepard-093"
    case poohSmall = "shepard-092"
    case poohWithPot = "shepard-088"        // Pooh carrying the honey pot
    case rabbit = "shepard-108"             // Rabbit, Piglet and Pooh
    case kangaRoo = "shepard-117"           // Kanga leaping with Roo
    case piglet = "shepard-123"             // Piglet in the bushes
    case beesTrail = "shepard-20-1"         // bees on the wing
    case poohDancing = "shepard-119"        // Pooh doing his stoutness exercises
    case poohThinking = "shepard-164"       // Pooh scratching his head
    case potOnHead = "shepard-82-2"         // Pooh with the pot stuck on his head
    case balloonHang = "shepard-29"         // Pooh hanging from the balloon with bees
    case balloonRise = "shepard-31"         // Pooh rising on the balloon
    case signpost = "shepard-143"           // Christopher Robin and Pooh at the North Pole signpost
    case honeyShelf = "shepard-150"         // the larder shelf of honey pots
    case eeyoreLying = "shepard-099"
    case eeyoreSad = "shepard-60"
    case eeyorePooh = "shepard-59"
    case eeyorePot = "shepard-103"          // Eeyore, Piglet and Pooh with the useful pot
    case owl = "shepard-66"                 // Owl in his parlour
    case poohsHouse = "shepard-25"          // the tree with Pooh's front door
    case walkingTrail = "shepard-28"        // Pooh walking off along a dotted trail
    case poohEeyoreSticks = "shepard-135"
}

/// One plate on the page, optionally on a watercolour wash. Decorative: hidden from VoiceOver.
struct Illustration: View {
    let plate: Plate
    var wash: Color? = nil
    var washOpacity: Double = 0.2
    var tint: Color = Theme.Colors.ink
    var opacity: Double = 1
    init(_ plate: Plate, wash: Color? = nil, washOpacity: Double = 0.2, tint: Color = Theme.Colors.ink, opacity: Double = 1) {
        self.plate = plate; self.wash = wash; self.washOpacity = washOpacity; self.tint = tint; self.opacity = opacity
    }
    var body: some View {
        Image(plate.rawValue)
            .resizable()
            .renderingMode(.template)
            .aspectRatio(contentMode: .fit)
            .foregroundStyle(tint)
            .opacity(opacity)
            .background {
                if let wash { WashBlob(color: wash, opacity: washOpacity).scaleEffect(1.12) }
            }
            .accessibilityHidden(true)
    }
}
