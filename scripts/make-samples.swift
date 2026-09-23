#!/usr/bin/env swift
// Rebuild original, synthetic Clevylo study fixtures using only macOS frameworks.
// Run from any directory: swift /path/to/Clevylo/scripts/make-samples.swift
import AppKit
import PDFKit
import CoreGraphics

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let output = root.appendingPathComponent("Samples", isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

let biology = """
# Cells, energy, and evidence

Original synthetic study material for Clevylo. No personal data.

## Cell membranes and diffusion

A cell membrane is a selectively permeable boundary. Some particles cross more readily than others. Diffusion is the net movement of particles from a region of higher concentration to a region of lower concentration because the particles move randomly. At equilibrium, particles still move, but there is no net movement in one direction.

Osmosis is the net movement of water through a selectively permeable membrane from higher water potential to lower water potential. In a simple school experiment, this is often described as water moving from a more dilute solution toward a more concentrated solution. Remember that the membrane must allow water through.

## Energy transformations

Photosynthesis uses light energy to build glucose from carbon dioxide and water, releasing oxygen. In plants, it takes place in chloroplasts.

Word equation: carbon dioxide + water + light energy -> glucose + oxygen

Aerobic cellular respiration transfers energy from glucose into forms cells can use, including ATP. It consumes oxygen and produces carbon dioxide and water. Plants carry out respiration as well as photosynthesis.

Word equation: glucose + oxygen -> carbon dioxide + water + released energy

Matter is rearranged; energy is transferred. Neither process creates matter from nothing.

## A fair investigation

A student investigates how lamp distance affects the rate of photosynthesis in pondweed. The student counts bubbles released in one minute at each distance. The independent variable is lamp distance. The dependent variable is bubbles per minute, a rough proxy for oxygen production. Keep temperature, pondweed length, carbon dioxide availability, and counting time consistent. Repeat trials and compare averages.

Bubbles may vary in volume, so bubble count is an imperfect measure. A gas-collection method could estimate oxygen volume more directly. A result can support a claim without proving that every possible alternative explanation has been excluded.

## Practice

1. Explain why diffusion can continue at equilibrium even though net movement is zero.
2. A plant is kept in darkness. Does it stop respiring? Explain.
3. Identify two controlled variables in the pondweed investigation.
4. Give one limitation of using bubble count to estimate oxygen production.

## Check your thinking

1. Individual particles keep moving randomly; movements in opposite directions balance overall.
2. No. Plant cells still need energy and can respire using stored glucose. Without light, photosynthesis cannot supply new glucose through its light-dependent process.
3. Examples: temperature, pondweed length, carbon dioxide availability, or counting time.
4. Different-sized bubbles contain different volumes of gas, so equal counts need not mean equal oxygen volumes.
"""

let algebra = """
LINEAR EQUATIONS AND CHECKING A SOLUTION
Original synthetic study material for Clevylo. No personal data.

Key idea
An equation states that two expressions have the same value. Applying the same reversible operation to both sides preserves the solution set. Keep each line balanced and check the final value in the original equation.

Worked example
Solve 3x + 5 = 20.
Subtract 5 from both sides: 3x = 15.
Divide both sides by 3: x = 5.
Check: 3(5) + 5 = 20.

Distributing correctly
2(x + 4) = 2x + 8 because the factor 2 multiplies every term inside the parentheses.
The expression 2x + 4 is not generally equal to 2(x + 4).

Practice
1. Solve 4x - 7 = 13.
2. Solve 2(x + 4) = 18.
3. A notebook costs $3. Four notebooks plus one pen cost $14. Find the pen's price.
4. A line has equation y = 2x + 1. Find y when x = -2 and when x = 3.
5. Check this claim: x = 4 solves 5x - 6 = 9.

Answers and explanations
1. Add 7 to get 4x = 20, then divide by 4: x = 5.
2. Divide by 2 to get x + 4 = 9, then subtract 4: x = 5.
3. Let p be the pen's price in dollars. 4(3) + p = 14, so p = 2. The pen costs $2.
4. At x = -2, y = -3. At x = 3, y = 7.
5. Substitution gives 5(4) - 6 = 14, not 9. The claim is false. Solving 5x = 15 gives x = 3.

Suggested study routine
Try a question without looking at its answer. Explain each operation aloud. Check the result by substitution. If an answer is wrong, identify the first line where the equality stopped being true.
"""

try biology.write(to: output.appendingPathComponent("Biology.md"), atomically: true, encoding: .utf8)
try algebra.write(to: output.appendingPathComponent("Algebra.txt"), atomically: true, encoding: .utf8)

let width: CGFloat = 612
let height: CGFloat = 792
let ink = NSColor(calibratedRed: 0.13, green: 0.16, blue: 0.22, alpha: 1)
let muted = NSColor(calibratedRed: 0.36, green: 0.40, blue: 0.47, alpha: 1)
let indigo = NSColor(calibratedRed: 0.25, green: 0.30, blue: 0.62, alpha: 1)
let pale = NSColor(calibratedRed: 0.94, green: 0.95, blue: 0.98, alpha: 1)

func text(_ value: String, x: CGFloat = 48, y: CGFloat, w: CGFloat = 516,
          size: CGFloat = 12, weight: NSFont.Weight = .regular, color: NSColor = ink,
          h: CGFloat = 90) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineSpacing = 4
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color, .paragraphStyle: paragraph
    ]
    (value as NSString).draw(in: CGRect(x: x, y: y, width: w, height: h), withAttributes: attributes)
}

func line(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat, color: NSColor = muted, thickness: CGFloat = 0.7) {
    color.setStroke()
    let path = NSBezierPath()
    path.move(to: NSPoint(x: x1, y: y1)); path.line(to: NSPoint(x: x2, y: y2)); path.lineWidth = thickness; path.stroke()
}

func box(_ rect: CGRect, color: NSColor = pale) {
    color.setFill(); NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7).fill()
}

func header(_ title: String, subtitle: String) {
    NSColor.white.setFill(); NSBezierPath(rect: CGRect(x: 0, y: 0, width: width, height: height)).fill()
    text("CLEVYLO  /  ORIGINAL SAMPLE", y: 38, size: 9, weight: .semibold, color: indigo, h: 18)
    text(title, y: 74, size: 27, weight: .bold, h: 44)
    text(subtitle, y: 118, size: 11, color: muted, h: 26)
    line(48, 157, 564, 157, color: indigo, thickness: 1.2)
}

func footer(_ number: Int, note: String) {
    line(48, 732, 564, 732, color: NSColor.lightGray)
    text(note, y: 745, size: 8, color: muted, h: 22)
    text(String(number), x: 545, y: 745, w: 19, size: 9, weight: .semibold, color: indigo, h: 22)
}

func biologyPage() {
    header("Cells, energy & evidence", subtitle: "Biology reading notes | embedded, selectable PDF text")
    text("01  Membranes and diffusion", y: 183, size: 15, weight: .semibold, color: indigo, h: 25)
    text("A cell membrane is selectively permeable: some particles cross more readily than others. Diffusion is net movement from higher to lower concentration. At equilibrium, particles still move randomly, but there is no net movement in one direction.", y: 220, h: 95)
    text("02  Two energy transformations", y: 324, size: 15, weight: .semibold, color: indigo, h: 25)
    text("Photosynthesis uses light energy to build glucose. Aerobic respiration releases usable energy from glucose. Plants carry out both processes.", y: 361, h: 66)
    box(CGRect(x: 48, y: 435, width: 516, height: 88))
    text("PHOTOSYNTHESIS", x: 64, y: 448, w: 484, size: 9, weight: .semibold, color: indigo, h: 16)
    text("carbon dioxide + water + light -> glucose + oxygen", x: 64, y: 468, w: 484, size: 12, h: 26)
    text("Matter is rearranged; energy is transferred.", x: 64, y: 496, w: 484, size: 10, color: muted, h: 20)
    text("03  Practice with evidence", y: 550, size: 15, weight: .semibold, color: indigo, h: 25)
    text("A pondweed experiment compares bubbles per minute at different lamp distances. Keep temperature, counting time, and carbon dioxide availability consistent. Repeat each trial. Bubble counts are approximate because bubbles can have different volumes.", y: 588, h: 93)
    text("Think: What does the student change, measure, and keep the same?", y: 686, size: 11, weight: .medium, h: 28)
    footer(1, note: "Original synthetic material. Full notes and answers: Biology.md and Algebra.txt.")
}

func worksheetPage() {
    header("Make the steps visible", subtitle: "Algebra worksheet | show your reasoning and check each answer")
    text("01  Solve and check", y: 183, size: 15, weight: .semibold, color: indigo, h: 25)
    text("4x - 7 = 13", y: 222, size: 22, weight: .medium, h: 34)
    text("Write one balanced operation on each line. Then substitute your answer.", y: 267, size: 11, color: muted, h: 27)
    for y: CGFloat in [319, 351, 383] { line(48, y, 564, y, color: NSColor(calibratedWhite: 0.81, alpha: 1)) }
    text("02  Read a relationship", y: 414, size: 15, weight: .semibold, color: indigo, h: 25)
    text("For y = 2x + 1, complete the table and plot the three points.", y: 449, size: 11, h: 32)
    box(CGRect(x: 48, y: 493, width: 206, height: 136))
    text("x", x: 68, y: 506, w: 45, size: 13, weight: .semibold, h: 25)
    text("y = 2x + 1", x: 139, y: 506, w: 105, size: 12, weight: .semibold, h: 25)
    line(61, 534, 242, 534, color: NSColor.lightGray)
    for (index, value) in ["-1", "0", "2"].enumerated() {
        text(value, x: 69, y: CGFloat(544 + index * 26), w: 55, size: 12, h: 25)
        line(142, CGFloat(562 + index * 26), 228, CGFloat(562 + index * 26), color: NSColor.lightGray)
    }
    // A simple original coordinate grid; 1 square = 1 unit on both axes.
    let left: CGFloat = 326, top: CGFloat = 488, step: CGFloat = 20
    for i in 0...10 {
        line(left + CGFloat(i) * step, top, left + CGFloat(i) * step, top + 180, color: NSColor(calibratedWhite: 0.88, alpha: 1), thickness: 0.5)
    }
    for i in 0...9 {
        line(left, top + CGFloat(i) * step, left + 200, top + CGFloat(i) * step, color: NSColor(calibratedWhite: 0.88, alpha: 1), thickness: 0.5)
    }
    let originX = left + 60, originY = top + 120
    line(left, originY, left + 214, originY, color: ink, thickness: 1)
    line(originX, top + 180, originX, top - 10, color: ink, thickness: 1)
    text("x", x: left + 218, y: originY - 9, w: 16, size: 10, h: 20)
    text("y", x: originX - 4, y: top - 29, w: 16, size: 10, h: 20)
    text("0", x: originX - 13, y: originY + 4, w: 16, size: 9, h: 20)
    text("1", x: originX + step - 3, y: originY + 4, w: 16, size: 9, h: 20)
    text("1", x: originX - 15, y: originY - step - 7, w: 16, size: 9, h: 20)
    text("1 square = 1 unit", x: 334, y: 682, w: 204, size: 9, color: muted, h: 20)
    text("Answers: x = 5; table values are -1, 1, and 5.", y: 703, size: 9, color: muted, h: 18)
    footer(2, note: "Original synthetic worksheet. In StudySample.pdf this page is an image for OCR practice.")
}

func draw(in context: CGContext, _ body: () -> Void) {
    context.saveGState()
    context.translateBy(x: 0, y: height); context.scaleBy(x: 1, y: -1)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
    body()
    NSGraphicsContext.restoreGraphicsState()
    context.restoreGState()
}

let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * 2), pixelsHigh: Int(height * 2),
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                              colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
let rasterContext = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext
rasterContext.scaleBy(x: 2, y: 2)
draw(in: rasterContext, worksheetPage)
guard let png = bitmap.representation(using: .png, properties: [:]), let worksheetImage = bitmap.cgImage else {
    fatalError("Could not encode the worksheet image.")
}
try png.write(to: output.appendingPathComponent("Worksheet.png"), options: .atomic)

var mediaBox = CGRect(x: 0, y: 0, width: width, height: height)
let pdfURL = output.appendingPathComponent("StudySample.pdf")
guard let consumer = CGDataConsumer(url: pdfURL as CFURL),
      let pdf = CGContext(consumer: consumer, mediaBox: &mediaBox, [kCGPDFContextTitle: "Clevylo original study samples", kCGPDFContextAuthor: "Clevylo sample material"] as CFDictionary) else {
    fatalError("Could not create the sample PDF.")
}
pdf.beginPDFPage(nil); draw(in: pdf, biologyPage); pdf.endPDFPage()
pdf.beginPDFPage(nil)
pdf.draw(worksheetImage, in: mediaBox)
pdf.endPDFPage(); pdf.closePDF()

guard let document = PDFDocument(url: pdfURL), document.pageCount == 2,
      document.page(at: 0)?.string?.contains("Photosynthesis") == true,
      (document.page(at: 1)?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
    fatalError("Sample verification failed: expected a text page followed by an image-only page.")
}
print("Created Biology.md, Algebra.txt, Worksheet.png, and StudySample.pdf (2 pages).")
print("Verified PDF text on page 1 and an image-only page 2 for OCR.")
