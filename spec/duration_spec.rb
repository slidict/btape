# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe Btape::Duration do
  it 'parses milliseconds and seconds into seconds' do
    expect(described_class.parse('500ms')).to eq(0.5)
    expect(described_class.parse('1.5s')).to eq(1.5)
  end

  it 'accepts only the ms and s suffixes' do
    expect(described_class).to be_valid('250ms')
    expect(described_class).not_to be_valid('250')
    expect(described_class).not_to be_valid('2m')
    expect(described_class).not_to be_valid('tomorrow')
  end

  it 'raises for a value it cannot parse' do
    expect { described_class.parse('tomorrow') }.to raise_error(ArgumentError, /must use ms or s/)
  end
end
