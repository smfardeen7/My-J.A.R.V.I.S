import AppKit
let output=CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath:output,withIntermediateDirectories:true)
for size in [16,32,64,128,256,512,1024] {
    let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:size,pixelsHigh:size,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:size*4,bitsPerPixel:32)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:bitmap)!
    let scale=CGFloat(size)/512
    let transform=NSAffineTransform();transform.scale(by:scale);transform.concat()
    NSColor(srgbRed:0.025,green:0.045,blue:0.065,alpha:1).setFill()
    NSBezierPath(roundedRect:NSRect(x:0,y:0,width:512,height:512),xRadius:108,yRadius:108).fill()
    for (radius,width,alpha) in [(190.0,3.0,0.5),(169.0,12.0,0.8),(140.0,3.0,0.6),(118.0,7.0,1.0),(88.0,2.0,0.5)] {
        NSColor(srgbRed:0,green:0.83,blue:1,alpha:alpha).setStroke()
        let ring=NSBezierPath(ovalIn:NSRect(x:256-radius,y:256-radius,width:radius*2,height:radius*2));ring.lineWidth=width
        if radius == 169 {var dash:[CGFloat]=[90,18];ring.setLineDash(&dash,count:2,phase:0)}
        ring.stroke()
    }
    NSGradient(starting:NSColor(srgbRed:0.75,green:0.98,blue:1,alpha:1),ending:NSColor(srgbRed:0,green:0.65,blue:0.9,alpha:0))!.draw(in:NSBezierPath(ovalIn:NSRect(x:180,y:180,width:152,height:152)),relativeCenterPosition:.zero)
    NSGraphicsContext.restoreGraphicsState()
    let data=bitmap.representation(using:.png,properties:[:])!
    let name=size == 1024 ? "icon_512x512@2x.png" : "icon_\(size)x\(size).png"
    if size != 64 {try data.write(to:URL(fileURLWithPath:output).appendingPathComponent(name))}
    if [32,64,256,512].contains(size) {try data.write(to:URL(fileURLWithPath:output).appendingPathComponent("icon_\(size/2)x\(size/2)@2x.png"))}
}
