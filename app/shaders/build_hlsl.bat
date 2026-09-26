fxc /T vs_5_0 /O3 /Fo d3d11_vertex.fxc d3d11_vertex.hlsl

fxc /T ps_5_0 /O3 /Fo d3d11_overlay_pixel.fxc d3d11_overlay_pixel.hlsl
fxc /T ps_5_0 /O3 /Fo d3d11_yuv420_pixel.fxc d3d11_yuv420_pixel.hlsl
fxc /T ps_5_0 /O3 /Fo d3d11_ayuv_pixel.fxc d3d11_ayuv_pixel.hlsl
fxc /T ps_5_0 /O3 /Fo d3d11_y410_pixel.fxc d3d11_y410_pixel.hlsl

fxc /T ps_5_0 /O3 /Fo d3d11_fi_blit_pixel.fxc d3d11_fi_blit_pixel.hlsl
fxc /T ps_5_0 /O3 /Fo d3d11_fi_interp_pixel.fxc d3d11_fi_interp_pixel.hlsl
fxc /T cs_5_0 /O3 /Fo d3d11_fi_pyramid_cs.fxc d3d11_fi_pyramid_cs.hlsl
fxc /T cs_5_0 /O3 /Fo d3d11_fi_motion_cs.fxc d3d11_fi_motion_cs.hlsl
fxc /T cs_5_0 /O3 /Fo d3d11_fi_filter_cs.fxc d3d11_fi_filter_cs.hlsl