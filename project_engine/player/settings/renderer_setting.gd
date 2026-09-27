class_name RendererSetting
extends RefCounted

## Which GPU driver the player starts with on Windows: Direct3D 12 (the
## default) or Vulkan. D3D12 is what lets the hardware video decoder
## (NativeVideoBackend) hand frames to the GPU without a CPU copy; Vulkan is
## the fallback should D3D12 misbehave, e.g. with a headset's runtime.
##
## The driver is picked before any script runs, so this can't live in
## PlayerSettings: it is written to the project-settings override file
## (application/config/project_settings_override in project.godot), which
## the engine reads at startup. A change applies on the next start.

const OVERRIDE_PATH := "user://override.cfg"
const SECTION := "rendering"
const KEY := "rendering_device/driver.windows"
## In dropdown order.
const DRIVERS := ["d3d12", "vulkan"]
const DRIVER_LABELS := {
	"d3d12": "Direct3D 12 — zero-copy hardware video",
	"vulkan": "Vulkan",
}


## Only Windows has the choice.
static func applies() -> bool:
	return OS.get_name() == "Windows"


## The driver running now.
static func active() -> String:
	return RenderingServer.get_current_rendering_driver_name()


## The driver the next start will use: the override file's, else the
## project default.
static func chosen() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(OVERRIDE_PATH) == OK and cfg.has_section_key(SECTION, KEY):
		return String(cfg.get_value(SECTION, KEY))
	return String(ProjectSettings.get_setting("rendering/" + KEY, "d3d12"))


static func choose(driver: String) -> Error:
	if not driver in DRIVERS:
		return ERR_INVALID_PARAMETER
	var cfg := ConfigFile.new()
	cfg.load(OVERRIDE_PATH)  # keep anything else in it
	cfg.set_value(SECTION, KEY, driver)
	return cfg.save(OVERRIDE_PATH)
