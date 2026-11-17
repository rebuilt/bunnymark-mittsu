# frozen_string_literal: true

require 'mittsu/opengl'

require_relative 'lib/game_logic'

# Fast sprite path: batches the homogeneous bunny sprites into far fewer GL
# calls (see lib/fast_sprites.rb). Disable with FAST=0 to use the stock
# per-sprite SpritePlugin renderer instead.
FAST_PATH = ENV['FAST'] != '0'
if FAST_PATH
  require_relative 'lib/fast_sprites'
  GameLogic.update_matrix_world_directly = true
end

SCREEN_WIDTH = 1280
SCREEN_HEIGHT = 720

puts "mittsu bunnymark (mittsu #{Mittsu::VERSION}, mittsu-opengl #{Mittsu::OpenGL::VERSION})"

texture = Mittsu::ImageUtils.load_texture(File.join(__dir__, 'resources', 'raybunny.png'))
base_material = Mittsu::SpriteMaterial.new(map: texture)

renderer = Mittsu::OpenGL::Renderer.new(width: SCREEN_WIDTH, height: SCREEN_HEIGHT, title: 'mittsu bunnymark')
window = renderer.window

# The gem forces vsync (SwapInterval 1) which caps a benchmark at the monitor
# refresh rate. Measure uncapped like raylib's bunnymark unless VSYNC=1.
GLFW.SwapInterval(ENV['VSYNC'] == '1' ? 1 : 0)

# Some window managers / DPI setups resize the requested window. The renderer
# already renders into the real framebuffer size, so use it everywhere.
FRAME_WIDTH, FRAME_HEIGHT = window.framebuffer_size
puts "window framebuffer: #{FRAME_WIDTH}x#{FRAME_HEIGHT}"

scene = Mittsu::Scene.new
scene.auto_update = false if FAST_PATH # fast path maintains matrix_world itself

# Orthographic camera spanning the window in screen space. With
# make_orthographic(left: 0, right: W, top: 0, bottom: H) the y axis
# increases *downwards*, exactly matching GLFW mouse coordinates.
camera = Mittsu::OrthographicCamera.new(0.0, FRAME_WIDTH.to_f, 0.0, FRAME_HEIGHT.to_f, 1.0, 1000.0)
camera.position.z = 10.0

renderer.set_clear_color(Mittsu::Color.new(0xffffff))

state = GameLogic::State.new
state.screen_width = FRAME_WIDTH
state.screen_height = FRAME_HEIGHT
state.scene = scene
state.texture = texture
state.base_material = base_material

GameLogic.init(state)

quit = false

window.on_key_pressed do |key|
  case key
  when GLFW::KEY_P then state.paused = !state.paused
  when GLFW::KEY_F5 then GameLogic.init(state)
  when GLFW::KEY_Q, GLFW::KEY_ESCAPE then quit = true
  end
end

adaptive = ENV['ADAPTIVE'] == '1'
screenshot = ENV['SCREENSHOT'] || ''
frames_to_screenshot = screenshot.empty? ? nil : 20
duration = ENV['DURATION'] ? Float(ENV['DURATION']) : nil

start_time = GLFW.GetTime
last_time = start_time

catch(:quit) do
  window.run do
    throw :quit if quit

    time = GLFW.GetTime
    dt = time - last_time
    last_time = time
    dt = 0.05 if dt > 0.05

    if window.mouse_button_down?(GLFW::MOUSE_BUTTON_LEFT)
      position = window.mouse_position
      GameLogic.create_bunnies_at(state, position.x, position.y, 100)
    end

    if window.mouse_button_down?(GLFW::MOUSE_BUTTON_RIGHT)
      GameLogic.destroy_bunnies(state, 10)
    end

    unless state.paused
      GameLogic.update(state, dt)
      GameLogic.update_bunny_count(state) if adaptive
    end

    renderer.render(scene, camera)

    state.frames += 1
    if time - state.fps_time >= 1.0
      state.fps = state.frames / (time - state.fps_time)
      state.frames = 0
      state.fps_time = time
      # Mittsu has no text rendering; each sprite is a single draw call, so
      # the HUD that raylib paints on screen goes to the console instead.
      puts format(
        'bunnies: %5d | fps: %3d | draw calls: %6d',
        state.bunnies.length, state.fps.round, state.bunnies.length + 1
      )
    end

    if frames_to_screenshot
      frames_to_screenshot -= 1
      if frames_to_screenshot.zero?
        # The gem's take_screenshot doesn't account for GL's default
        # PACK_ALIGNMENT=4, which pads RGB rows to a 4-byte stride and can
        # overflow the buffer it allocates when the width isn't a multiple
        # of 4 (e.g. a WM resized our window to 634 or 378 wide). Read
        # tightly-packed rows instead.
        GL.PixelStorei(GL::PACK_ALIGNMENT, 1)
        renderer.take_screenshot(screenshot, width: FRAME_WIDTH, height: FRAME_HEIGHT)
        throw :quit
      end
    end

    if duration && (time - start_time) >= duration
      throw :quit
    end
  end
end