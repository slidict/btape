# frozen_string_literal: true

require_relative 'spec_helper'
require 'tmpdir'

RSpec.describe Btape::GifEncoder do
  it 'writes an animated gif without an external process' do
    Dir.mktmpdir do |directory|
      frames = %w[red blue].map.with_index do |colour, index|
        path = File.join(directory, "#{index}.png")
        ChunkyPNG::Image.new(2, 2, ChunkyPNG::Color(colour)).save(path)
        path
      end
      output = File.join(directory, 'result.gif')

      described_class.new.write(frames, output)

      data = File.binread(output)
      expect(data).to start_with('GIF89a')
      expect(data.scan("\x21\xF9\x04".b).length).to eq(2)
      expect(data).to end_with(';')
    end
  end
end
