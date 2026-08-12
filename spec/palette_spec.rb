# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe Btape::Palette do
  # How far the palette's answer sits from the colour it was asked about,
  # averaged over the image. This is the number an adaptive palette exists to
  # bring down.
  def average_error(palette, image)
    table = palette.to_gct
    total = image.pixels.sum do |pixel|
      index = palette.index_for(pixel)
      colour = table[index * 3, 3].bytes
      wanted = [ChunkyPNG::Color.r(pixel), ChunkyPNG::Color.g(pixel), ChunkyPNG::Color.b(pixel)]
      Math.sqrt(wanted.zip(colour).sum { |want, got| (want - got)**2 })
    end
    total / image.pixels.length
  end

  def gradient(width: 64, height: 8)
    ChunkyPNG::Image.new(width, height).tap do |image|
      image.height.times do |y|
        image.width.times { |x| image[x, y] = ChunkyPNG::Color.rgb(20 + (x * 3), 40, 90 + (x * 2)) }
      end
    end
  end

  describe described_class::Fixed do
    it 'fills the whole colour table' do
      expect(described_class.new.to_gct.bytesize).to eq(768)
    end

    it 'maps a colour to its rgb332 cell' do
      expect(described_class.new.index_for(ChunkyPNG::Color.rgb(255, 255, 255))).to eq(255)
      expect(described_class.new.index_for(ChunkyPNG::Color.rgb(0, 0, 0))).to eq(0)
    end
  end

  describe described_class::Adaptive do
    it 'fills the whole colour table' do
      palette = described_class.from([gradient])

      expect(palette.to_gct.bytesize).to eq(768)
    end

    it 'spends a single colour on a single-colour image' do
      image = ChunkyPNG::Image.new(8, 8, ChunkyPNG::Color.rgb(30, 144, 255))

      palette = described_class.from([image])

      expect(palette.colours.length).to eq(1)
      expect(palette.index_for(image[0, 0])).to eq(0)
    end

    it 'gives distinct colours distinct indexes' do
      red = ChunkyPNG::Color.rgb(220, 20, 20)
      blue = ChunkyPNG::Color.rgb(20, 20, 220)
      image = ChunkyPNG::Image.new(2, 1)
      image[0, 0] = red
      image[1, 0] = blue

      palette = described_class.from([image])

      expect(palette.index_for(red)).not_to eq(palette.index_for(blue))
    end

    # The fixed palette has eight levels of red and four of blue to spend on
    # the whole cube, wherever the image actually sits in it.
    it 'tracks a gradient far more closely than the fixed palette' do
      image = gradient

      adaptive = average_error(described_class.from([image]), image)
      fixed = average_error(Btape::Palette::Fixed.new, image)

      expect(adaptive).to be < (fixed / 4)
    end

    it 'chooses its colours across every frame it is given' do
      red = ChunkyPNG::Image.new(4, 4, ChunkyPNG::Color.rgb(220, 20, 20))
      blue = ChunkyPNG::Image.new(4, 4, ChunkyPNG::Color.rgb(20, 20, 220))

      palette = described_class.from([red, blue])

      expect(palette.index_for(red[0, 0])).not_to eq(palette.index_for(blue[0, 0]))
    end

    it 'stays within the 256 colours a gif table holds' do
      noisy = ChunkyPNG::Image.new(64, 64)
      64.times { |y| 64.times { |x| noisy[x, y] = ChunkyPNG::Color.rgb(x * 4, y * 4, (x + y) * 2) } }

      expect(described_class.from([noisy]).colours.length).to be <= 256
    end
  end

  describe '.build' do
    it 'picks the quantizer by name' do
      expect(described_class.build(:rgb332, [])).to be_a(described_class::Fixed)
      expect(described_class.build('adaptive', [gradient])).to be_a(described_class::Adaptive)
    end
  end
end
