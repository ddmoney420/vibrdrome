//  Phase 0 spike bridging header — exposes MGLKit + GLES3 to Swift.
//  Mirrors MetalANGLE's own MGLKitSampleSwiftApp/MetalANGLE-BridgingHeader.h.
#ifndef ProjectMSpike_Bridging_Header_h
#define ProjectMSpike_Bridging_Header_h

#import <MetalANGLE/MGLKViewController.h>
#import <MetalANGLE/GLES3/gl3.h>
#import <MetalANGLE/EGL/egl.h>   // eglGetProcAddress — fed to projectM's GL loader

#endif /* ProjectMSpike_Bridging_Header_h */
