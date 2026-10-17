import AppKit

// Uso: swift btp-make-icon.swift ENTRADA(.ico/.png/.icns) SAIDA.png
// Gera a arte 1024x1024 no estilo dos ícones do BTP (fundo escuro arredondado),
// usando a maior resolução disponível dentro do arquivo de entrada.
let args = CommandLine.arguments
guard args.count >= 3, let src = NSImage(contentsOfFile: args[1]) else {
    FileHandle.standardError.write("ícone de entrada inválido\n".data(using: .utf8)!)
    exit(1)
}
let best = src.representations.max(by: { $0.pixelsWide * $0.pixelsHigh < $1.pixelsWide * $1.pixelsHigh })
let pixels = best?.pixelsWide ?? 32

let size = 1024
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
// Ícones pequenos (32px) ficam nítidos ampliados sem suavização; os grandes, suavizados.
NSGraphicsContext.current?.imageInterpolation = pixels < 128 ? .none : .high
let iconRect = NSRect(x: 84, y: 84, width: 856, height: 856)
let path = NSBezierPath(roundedRect: iconRect, xRadius: 192, yRadius: 192)
NSColor(calibratedRed: 0.06, green: 0.06, blue: 0.07, alpha: 1.0).setFill()
path.fill()
path.addClip()
let inner = NSRect(x: 140, y: 140, width: 744, height: 744)
if let best = best {
    best.draw(in: inner, from: .zero, operation: .sourceOver, fraction: 1.0, respectFlipped: true, hints: nil)
} else {
    src.draw(in: inner, from: .zero, operation: .sourceOver, fraction: 1.0)
}
NSColor(calibratedWhite: 1.0, alpha: 0.18).setStroke()
path.lineWidth = 6
path.stroke()
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
