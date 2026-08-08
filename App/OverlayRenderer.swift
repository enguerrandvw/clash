import UIKit
import CoreGraphics

// Format calqué sur la Dynamic Island compacte de l'iPhone 14 Pro :
// ~167 x 37 pt, soit un rapport de 4,55:1.
enum OverlayRenderer {

    static let width = 560
    static let height = 123

    private static let purple     = UIColor(red: 0.74, green: 0.38, blue: 1.00, alpha: 1)
    private static let purpleDim  = UIColor(red: 0.26, green: 0.14, blue: 0.38, alpha: 1)

    static func draw(into ctx: CGContext, elixir: Double, rate: Int, hand: [String]) {

        let w = CGFloat(width), h = CGFloat(height)

        ctx.setFillColor(UIColor.black.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))

        UIGraphicsPushContext(ctx)
        defer { UIGraphicsPopContext() }

        let pad: CGFloat = 22

        // ---- Chiffre, aligné à gauche ----
        let value = String(format: "%.1f", elixir)
        let numFont = UIFont.systemFont(ofSize: 82, weight: .bold)
        let numAttr: [NSAttributedString.Key: Any] = [
            .font: numFont,
            .foregroundColor: UIColor.white
        ]
        let numSize = (value as NSString).size(withAttributes: numAttr)
        let numY = (h - numSize.height) / 2
        (value as NSString).draw(at: CGPoint(x: pad, y: numY), withAttributes: numAttr)

        // ---- Goutte ----
        let dropX = pad + numSize.width + 12
        let dropH: CGFloat = 40
        drawDrop(ctx: ctx, rect: CGRect(x: dropX, y: (h - dropH) / 2,
                                        width: dropH * 0.72, height: dropH))

        // ---- Badge de vitesse, coin haut droit ----
        var barRight = w - pad
        if rate > 1 {
            let badge = "x\(rate)"
            let bFont = UIFont.systemFont(ofSize: 30, weight: .heavy)
            let bAttr: [NSAttributedString.Key: Any] = [
                .font: bFont,
                .foregroundColor: rate == 3 ? UIColor.systemOrange : UIColor.systemYellow
            ]
            let bSize = (badge as NSString).size(withAttributes: bAttr)
            (badge as NSString).draw(at: CGPoint(x: w - pad - bSize.width,
                                                 y: (h - bSize.height) / 2),
                                     withAttributes: bAttr)
            barRight = w - pad - bSize.width - 16
        }

        // ---- Barre segmentée, à droite du chiffre ----
        let barLeft = dropX + dropH * 0.72 + 20
        let available = max(0, barRight - barLeft)
        let gap: CGFloat = 4
        let segW = (available - gap * 9) / 10
        let barH: CGFloat = 44
        let barY = (h - barH) / 2

        if segW > 2 {
            for i in 0..<10 {
                let x = barLeft + CGFloat(i) * (segW + gap)
                let rect = CGRect(x: x, y: barY, width: segW, height: barH)
                let path = UIBezierPath(roundedRect: rect, cornerRadius: 4)

                ctx.setFillColor(purpleDim.cgColor)
                ctx.addPath(path.cgPath)
                ctx.fillPath()

                let fill = min(1, max(0, elixir - Double(i)))
                if fill > 0 {
                    ctx.saveGState()
                    ctx.addPath(path.cgPath)
                    ctx.clip()
                    ctx.setFillColor(purple.cgColor)
                    ctx.fill(CGRect(x: x, y: barY, width: segW * CGFloat(fill), height: barH))
                    ctx.restoreGState()
                }
            }
        }
    }

    private static func drawDrop(ctx: CGContext, rect: CGRect) {
        let p = UIBezierPath()
        let midX = rect.midX
        p.move(to: CGPoint(x: midX, y: rect.minY))
        p.addCurve(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.62),
                   controlPoint1: CGPoint(x: midX + rect.width * 0.22, y: rect.minY + rect.height * 0.24),
                   controlPoint2: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.42))
        p.addArc(withCenter: CGPoint(x: midX, y: rect.minY + rect.height * 0.62),
                 radius: rect.width / 2,
                 startAngle: 0, endAngle: .pi, clockwise: true)
        p.addCurve(to: CGPoint(x: midX, y: rect.minY),
                   controlPoint1: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.42),
                   controlPoint2: CGPoint(x: midX - rect.width * 0.22, y: rect.minY + rect.height * 0.24))
        p.close()
        ctx.setFillColor(purple.cgColor)
        ctx.addPath(p.cgPath)
        ctx.fillPath()
    }
}
