# frozen_string_literal: true

require 'chunky_png'

module Btape
  # The 256 colours a GIF frame is written in, and the mapping from a pixel to
  # one of them.
  #
  # Fixed spreads its colours evenly across the whole RGB cube regardless of
  # what is being encoded, which costs nothing to build but wastes most of the
  # palette on colours the image does not contain. Adaptive chooses the
  # colours from the image itself, which is what keeps text edges and
  # gradients from banding.
  module Palette
    SIZE = 256
    # Colours are bucketed to five bits per channel before anything looks at
    # them. It collapses a screenshot's million pixels into a few thousand
    # distinct entries, and the error it introduces is below what the 256
    # colours of a GIF can express anyway.
    LEVELS = 32
    CELLS = LEVELS**3

    module_function

    def build(quantizer, images)
      quantizer.to_sym == :adaptive ? Adaptive.from(images) : Fixed.new
    end

    def cell(pixel)
      ((ChunkyPNG::Color.r(pixel) >> 3) << 10) |
        ((ChunkyPNG::Color.g(pixel) >> 3) << 5) |
        (ChunkyPNG::Color.b(pixel) >> 3)
    end

    def rgb(cell)
      [((cell >> 10) & 31) * 255 / 31, ((cell >> 5) & 31) * 255 / 31, (cell & 31) * 255 / 31]
    end

    # Pads a list of colours out to a full global colour table.
    def colour_table(colours)
      colours.map { |colour| colour.pack('C3') }.join.b.ljust(SIZE * 3, "\x00".b)
    end

    # Three bits of red, three of green, two of blue. Cheap, and independent
    # of the image, but only eight distinct levels of red to spend on a
    # gradient that may need far more.
    class Fixed
      def index_for(pixel)
        (ChunkyPNG::Color.r(pixel) & 0xe0) |
          ((ChunkyPNG::Color.g(pixel) & 0xe0) >> 3) |
          (ChunkyPNG::Color.b(pixel) >> 6)
      end

      def to_gct
        Palette.colour_table(
          (0...SIZE).map { |i| [((i >> 5) & 7) * 255 / 7, ((i >> 2) & 7) * 255 / 7, (i & 3) * 255 / 3] }
        )
      end
    end

    # Colours chosen from the frames themselves by median cut.
    class Adaptive
      # Enough of each frame to describe what colours it uses. Reading every
      # pixel of every frame would cost far more and change the answer very
      # little.
      MAX_SAMPLES_PER_IMAGE = 60_000

      def self.from(images)
        new(histogram(images))
      end

      def self.histogram(images)
        counts = Hash.new(0)
        images.each do |image|
          pixels = image.pixels
          stride = [pixels.length / MAX_SAMPLES_PER_IMAGE, 1].max
          index = 0
          while index < pixels.length
            counts[Palette.cell(pixels[index])] += 1
            index += stride
          end
        end
        counts
      end

      def initialize(histogram)
        @colours = MedianCut.new(histogram).colours
        # One entry per five-bit colour cell, filled in as cells are met. A
        # screenshot touches a small fraction of them, so searching the
        # palette for the rest would be work thrown away.
        @lookup = Array.new(CELLS)
      end

      attr_reader :colours

      def index_for(pixel)
        cell = Palette.cell(pixel)
        @lookup[cell] || (@lookup[cell] = nearest(cell))
      end

      def to_gct
        Palette.colour_table(@colours)
      end

      private

      def nearest(cell)
        red, green, blue = Palette.rgb(cell)
        best = 0
        shortest = nil
        @colours.each_with_index do |(r, g, b), index|
          distance = ((red - r)**2) + ((green - g)**2) + ((blue - b)**2)
          next unless shortest.nil? || distance < shortest

          shortest = distance
          best = index
        end
        best
      end
    end

    # Repeatedly splits the colours in use along their widest axis, so that
    # each of the 256 boxes it ends up with holds a similar share of the
    # pixels. Colours a frame leans on get more of the palette than colours it
    # barely touches.
    class MedianCut
      # Colours in a box, as [red, green, blue, weight] entries. The stats a
      # split needs are worked out once per box: they are read every round,
      # and the box they describe never changes.
      class Box
        def initialize(entries)
          @entries = entries
          @bounds = compute_bounds
          @axis = (0..2).max_by { |channel| @bounds[channel].last - @bounds[channel].first }
          @weight = entries.sum(&:last)
        end

        attr_reader :entries, :axis, :weight

        def splittable?
          @entries.length > 1
        end

        # Both how far the box spreads and how many pixels are in it: a wide
        # box nothing is using does not deserve the palette entry.
        def priority
          (@bounds[@axis].last - @bounds[@axis].first) * @weight
        end

        def split
          sorted = @entries.sort_by { |entry| entry[@axis] }
          [Box.new(sorted.shift(median_index(sorted))), Box.new(sorted)]
        end

        def colour
          (0..2).map { |channel| @entries.sum { |entry| entry[channel] * entry.last } / @weight }
        end

        private

        def compute_bounds
          (0..2).map { |channel| @entries.map { |entry| entry[channel] }.minmax }
        end

        # Splits where half the weight lies, leaving at least one entry each
        # side however lopsided the weights are.
        def median_index(sorted)
          half = @weight / 2.0
          running = 0
          taken = sorted.take_while do |entry|
            running += entry.last
            running < half
          end.length
          taken.clamp(1, sorted.length - 1)
        end
      end

      def initialize(histogram, size: SIZE)
        @entries = histogram.map { |cell, weight| Palette.rgb(cell) << weight }
        @size = size
      end

      def colours
        return [[0, 0, 0]] if @entries.empty?

        boxes = [Box.new(@entries)]
        while boxes.length < @size
          index = widest(boxes)
          break unless index

          boxes[index, 1] = boxes[index].split
        end
        boxes.map(&:colour)
      end

      private

      def widest(boxes)
        boxes.each_index.select { |index| boxes[index].splittable? }.max_by { |index| boxes[index].priority }
      end
    end
  end
end
