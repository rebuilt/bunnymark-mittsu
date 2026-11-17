# frozen_string_literal: true

# Sprite bunnymark game logic for Mittsu.
#
# Mirrors the classic raylib bunnymark (spawn while holding the mouse,
# bounce off the walls) plus the ruby/raylib port's extras (right-click
# destroy, adaptive count, reset). Positions are quad-center based so that
# they map directly onto Mittsu::Sprite positions.
module GameLogic
  MAX_BUNNIES = 200_000

  BUNNY_WIDTH  = 32.0
  BUNNY_HEIGHT = 32.0
  HALF_WIDTH   = BUNNY_WIDTH / 2.0
  HALF_HEIGHT  = BUNNY_HEIGHT / 2.0

  # Height of the region along the top of the screen that bunnies may not
  # fully enter (where the raylib original drew its HUD text).
  TOP_BAR = 40.0

  Bunny = Struct.new(:x, :y, :dx, :dy, :color, :sprite)

  State = Struct.new(
    :screen_width, :screen_height, :scene, :texture, :base_material,
    :bunnies, :paused, :time, :fps_time, :frames, :fps
  ) do
    def reset_structure
      self.bunnies = []
      self.scene.children.clear
      self.paused = false
      self.time = GLFW.GetTime
      self.fps_time = time
      self.frames = 0
      self.fps = 0
    end
  end

  class << self
    # When the fast sprite renderer is active (lib/fast_sprites.rb) the scene
    # graph's matrix compose is bypassed: each sprite's matrix_world is written
    # directly from the simulation, so this toggles that behaviour on. Off by
    # default so the stock renderer keeps working untouched.
    attr_accessor :update_matrix_world_directly

    def init(state)
      state.reset_structure

      count = Integer(ENV['BUNNY_COUNT'] || 2500, exception: false) || 2500
      create_bunnies(state, count)
    end

    def update(state, dt)
      bunnies = state.bunnies
      count = bunnies.length
      width = state.screen_width
      height = state.screen_height

      i = 0
      while i < count
        bunny = bunnies[i]
        bunny.x += bunny.dx * dt
        bunny.y += bunny.dy * dt

        bunny.dx = -bunny.dx if bunny.x - HALF_WIDTH < 0.0 || bunny.x + HALF_WIDTH > width
        bunny.dy = -bunny.dy if bunny.y - HALF_HEIGHT < TOP_BAR || bunny.y + HALF_HEIGHT > height

        sprite = bunny.sprite
        sprite.position.x = bunny.x
        sprite.position.y = bunny.y
        if update_matrix_world_directly
          elements = sprite.matrix_world.elements
          elements[12] = bunny.x
          elements[13] = bunny.y
        end

        i += 1
      end
    end

    def create_bunnies(state, count)
      count.times do
        break if state.bunnies.length >= MAX_BUNNIES
        state.bunnies << build_bunny(state)
      end
    end

    def create_bunnies_at(state, x, y, count)
      count.times do
        break if state.bunnies.length >= MAX_BUNNIES
        state.bunnies << build_bunny(state, x, y)
      end
    end

    def destroy_bunnies(state, count)
      count = [count, state.bunnies.length].min
      count.times do
        state.bunnies.pop
        state.scene.children.pop
      end
    end

    # Ruby/raylib-style adaptive count: every second, add bunnies while we
    # hold 60fps, remove a few when we don't.
    def update_bunny_count(state)
      t = GLFW.GetTime
      return if t - state.time < 1.0
      state.time = t

      if state.fps >= 60
        create_bunnies(state, 100)
      else
        destroy_bunnies(state, 5)
      end
    end

    private

    def build_bunny(state, x = nil, y = nil)
      x ||= rand(0.0..state.screen_width)
      y ||= rand(TOP_BAR..(state.screen_height - BUNNY_HEIGHT))

      material = state.base_material.clone
      material.color.set_rgb(
        rand(50..240) / 255.0,
        rand(80..240) / 255.0,
        rand(100..240) / 255.0
      )

      sprite = Mittsu::Sprite.new(material)
      sprite.position.set(x, y, 0.0)
      sprite.scale.set(BUNNY_WIDTH, BUNNY_HEIGHT, 1.0)
      if update_matrix_world_directly
        # Fast renderer maintains matrix_world directly; stop the scene graph
        # from recomposing it (this also keeps identity rotation/scale out of
        # the matrix, which the sprite shader ignores anyway).
        sprite.matrix_auto_update = false
        sprite.matrix_world_needs_update = false
        sprite.matrix_world.identity
      end
      state.scene.add(sprite)

      Bunny.new(
        x.to_f, y.to_f,
        rand(-250.0..250.0), rand(-250.0..250.0),
        material.color.clone, sprite
      )
    end
  end
end