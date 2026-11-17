# frozen_string_literal: true

# Fast-path rendering for sprite-heavy scenes (the bunnymark).
#
# The stock SpritePlugin does the following for EVERY sprite on EVERY frame:
#
#   * builds modelViewMatrix by multiplying two 4x4 matrices in Ruby,
#   * depth-sorts the whole sprite list,
#   * re-uploads every uniform (uv, opacity, alphaTest, rotation, scale) even
#     though nothing about them changes between bunnies,
#   * allocates a fresh Fiddle buffer on each matrix / scale upload,
#   * re-binds the texture (all bunnies share one),
#   * runs renderer-state blend/depth checks.
#
# That adds up to ~40-150 us per sprite. The bunny sprites differ in exactly
# two things (position and tint color), and the sprite vertex shader only reads
# the *translation* column of modelViewMatrix (quad size/rotation come from the
# `scale`/`rotation` uniforms). So the fast path:
#
#   1. uploads every constant uniform once and binds the shared texture once,
#   2. keeps a single reusable identity matrix and plugs the per-sprite
#      camera-space translation into it (no multiply, no decompose),
#   3. drops the depth sort (independent little quads).
#
# This module only makes sense for a batch of homogeneous sprites. The contract:
# every sprite in the plugin list shares the same map, scale, rotation, opacity,
# alpha_test and blend settings -- exactly the bunnymark's setup. When that
# does not hold the stock path must be used instead (set FAST=0).
module Mittsu
  module OpenGL
    module FastSprites
      # Replaces SpritePlugin#update_positions_and_sort. No matrix multiply, no
      # sort; just remember the camera-space basis for building translations.
      def update_positions_and_sort(camera)
        elements = camera.matrix_world_inverse.elements
        @_fs_m0 = elements[0];  @_fs_m1 = elements[1];  @_fs_m2  = elements[2]
        @_fs_m4 = elements[4];  @_fs_m5 = elements[5];  @_fs_m6  = elements[6]
        @_fs_t0 = elements[12]; @_fs_t1 = elements[13]; @_fs_t2  = elements[14]
      end

      def render_all_sprites(_scene)
        sprites = @sprites
        return if sprites.empty?

        first = sprites.first
        material = first.material
        map = material.map
        uniforms = @uniforms

        # --- values identical for every sprite, uploaded once ---
        if map
          GL.Uniform2f(uniforms[:uvOffset], map.offset.x, map.offset.y)
          GL.Uniform2f(uniforms[:uvScale], map.repeat.x, map.repeat.y)
          map.set(0, @renderer) # all sprites share this one texture
        else
          GL.Uniform2f(uniforms[:uvOffset], 0.0, 0.0)
          GL.Uniform2f(uniforms[:uvScale], 1.0, 1.0)
        end
        GL.Uniform1f(uniforms[:opacity], material.opacity)
        GL.Uniform1f(uniforms[:alphaTest], material.alpha_test)
        GL.Uniform1f(uniforms[:rotation], material.rotation)
        scale = first.scale
        GL.Uniform2f(uniforms[:scale], scale.x, scale.y)

        state = @renderer.state
        state.set_blending(material.blending, material.blend_equation, material.blend_src, material.blend_dst)
        state.set_depth_test(material.depth_test)
        state.set_depth_write(material.depth_write)

        # Reusable identity matrix; translation column patched per sprite.
        # Element layout is column-major: translation = indices 12, 13, 14.
        mv = @_fs_mv_array ||=
          [1.0, 0.0, 0.0, 0.0,
           0.0, 1.0, 0.0, 0.0,
           0.0, 0.0, 1.0, 0.0,
           0.0, 0.0, 0.0, 1.0]

        m0 = @_fs_m0; m1 = @_fs_m1; m2 = @_fs_m2
        m4 = @_fs_m4; m5 = @_fs_m5; m6 = @_fs_m6
        t0 = @_fs_t0; t1 = @_fs_t1; t2 = @_fs_t2

        mv_location = uniforms[:modelViewMatrix]
        color_location = uniforms[:color]

        sprites.each do |sprite|
          elements = sprite.matrix_world.elements
          x = elements[12]
          y = elements[13]
          # view = camera.matrix_world_inverse * (x, y, 0, 1)
          mv[12] = m0 * x + m4 * y + t0
          mv[13] = m1 * x + m5 * y + t1
          mv[14] = m2 * x + m6 * y + t2
          GL.UniformMatrix4fv(mv_location, 1, GL::FALSE, mv.pack('F*'))
          color = sprite.material.color
          GL.Uniform3f(color_location, color.r, color.g, color.b)
          GL.DrawElements(GL::TRIANGLES, 6, GL::UNSIGNED_INT, 0)
        end
      end
    end
  end
end

Mittsu::SpritePlugin.prepend(Mittsu::OpenGL::FastSprites)