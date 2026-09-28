// Shader time follows the video (see MediaTime): TIME is the playhead,
// stopped while paused and jumping with seeks, rather than seconds since
// the app started. The preludes include this; VisualizerShaders puts it
// into shaders that include no prelude too. A shader with a `// @free_time`
// line gets VJ_FREE_TIME defined first and keeps Godot's own TIME.
// Include guarded, so a second include does nothing.

#ifndef VJ_MEDIA_TIME
#define VJ_MEDIA_TIME
#ifndef VJ_FREE_TIME
global uniform float vj_time;
#define TIME vj_time
#endif
#endif
