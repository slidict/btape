# frozen_string_literal: true

module Btape
  class GifEncoder
    # Variable-width LZW compression of a flat array of palette indices,
    # producing (code, width) pairs ready for bit-packing into a GIF stream.
    class LzwCompressor
      CLEAR_CODE = 256
      FINISH_CODE = 257
      MAX_CODE_WIDTH = 12
      MAX_DICTIONARY_SIZE = 1 << MAX_CODE_WIDTH

      # Mutable state threaded through compress/advance: the growing code
      # dictionary, the next free code, the current code width in bits, and
      # whether a width bump is owed (see #advance).
      State = Struct.new(:dictionary, :next_code, :code_width, :pending_width_bump)

      def call(pixels, &emit)
        emit.call(CLEAR_CODE, 9)
        return emit.call(FINISH_CODE, 9) if pixels.empty?

        compress(pixels, emit)
      end

      private

      def compress(pixels, emit)
        state = State.new(root_dictionary, FINISH_CODE + 1, 9, false)
        current_code = pixels.first

        pixels.drop(1).each do |pixel|
          key = ((current_code + 1) << 8) | pixel
          if state.dictionary.key?(key)
            current_code = state.dictionary[key]
            next
          end

          emit.call(current_code, state.code_width)
          advance(state, key, emit)
          current_code = pixel
        end

        emit.call(current_code, state.code_width)
        emit.call(FINISH_CODE, state.code_width)
      end

      # A GIF decoder cannot add its own dictionary entry until it has seen two
      # codes (it has nothing to extend after just the first), so its
      # code-width bump for a given dictionary slot always lands one code later
      # than the encoder's. Deferring the bump by one entry here keeps the two
      # in lockstep.
      def advance(state, key, emit)
        if state.next_code == MAX_DICTIONARY_SIZE
          emit.call(CLEAR_CODE, state.code_width)
          return reset!(state)
        end

        state.dictionary[key] = state.next_code
        state.next_code += 1
        if state.pending_width_bump
          state.code_width += 1 if state.code_width < MAX_CODE_WIDTH
          state.pending_width_bump = false
        end
        state.pending_width_bump = true if state.next_code > (1 << state.code_width) - 1
      end

      def reset!(state)
        state.dictionary = root_dictionary
        state.next_code = FINISH_CODE + 1
        state.code_width = 9
        state.pending_width_bump = false
      end

      def root_dictionary
        (0..255).to_h { |value| [value, value] }
      end
    end
  end
end
