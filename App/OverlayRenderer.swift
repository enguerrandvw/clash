import UIKit
import CoreGraphics

// Dessine l'image affichée dans la fenêtre flottante.
// Tout est vectoriel : chiffre, barre segmentée, badge de vitesse.
enum OverlayRenderer {

    static let width = 480
    static let height = 180

    private static let purple = UIColor(red: 0.72, green: 0.35, blue: 0.98, alpha: 1)
    private static let purpleDim = UIColor(red: 0.30, green: 0.16, blue: 0.44, alpha: 1)

    static func draw(into ctx: CGContext, elixir: Double, rate: Int, hand: [String]) {

        let w = CGFloat(width), h = CGFloat(height)

        // Fond
        ctx.setFillColor(UIColor(white: 0.04, alpha: 1).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))

        UIGraphicsPushContext(ctx)
        defer { UIGraphicsPopContext() }

        // ---- Chiffre principal ----
        let value = String(format: "%.1f", elixir)
        let numFont = UIFont.systemFont(ofSize: 96, weight: .bold)
        let numAttr: [NSAttributedString.Key: Any] = [
            .font: numFont,
            .foregroundColor: UIColor.white
        ]
        let numSize = (value as NSString).size(withAttributes: numAttr)
        (value as NSString).draw(at: CGPoint(x: 28, y: 18), withAttributes: numAttr)

        // Goutte à gauche du chiffre
        drawDrop(ctx: ctx, rect: CGRect(x: 28 + numSize.width + 16, y: 44, width: 34, height: 44))

        // ---- Badge de vitesse ----
        if rate > 1 {
            let badge = "x\(rate)"
            let bFont = UIFont.systemFont(ofSize: 34, weight: .heavy)
            let bAttr: [NSAttributedString.Key: Any] = [
                .font: bFont,
                .foregroundColor: rate == 3 ? UIColor.systemOrange : UIColor.systemYellow
            ]
            let bSize = (badge as NSString).size(withAttributes: bAttr)
            (badge as NSString).draw(at: CGPoint(x: w - bSize.width - 28, y: 22),
                                     withAttributes: bAttr)
        }

        // ---- Barre segmentée en 10 ----
        let barY = h - 52
        let barH: CGFloat = 26
        let margin: CGFloat = 28
        let gap: CGFloat = 5
        let segW = (w - margin * 2 - gap * 9) / 10

        for i in 0..<10 {
            let x = margin + CGFloat(i) * (segW + gap)
            let rect = CGRect(x: x, y: barY, width: segW, height: barH)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 5)

            // Fond du segment
            ctx.setFillColor(purpleDim.withAlphaComponent(0.45).cgColor)
            ctx.addPath(path.cgPath)
            ctx.fillPath()

            // Remplissage partiel
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

    // Petite goutte d'élixir stylisée
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
