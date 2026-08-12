# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe Btape::LLM::Generator do
  # Answers the replies it was given, in order, and remembers what it was
  # asked — which is where the repair loop can be seen working.
  let(:fake_client_class) do
    Struct.new(:replies, :conversations) do
      def model = 'a-local-model'

      def complete(messages)
        self.conversations = conversations.to_a + [messages]
        raise 'asked more often than the fake had answers' if replies.empty?

        replies.shift
      end
    end
  end

  def client(*replies) = fake_client_class.new(replies)

  let(:tape) { "Output demo.gif\nGoto http://localhost:3000\nWaitFor \"text=Hello\"\n" }

  it 'returns the tape the model wrote' do
    expect(described_class.new(client: client(tape)).call('record the home page')).to eq(tape)
  end

  it 'takes the tape out of a fenced block and leaves the prose behind' do
    reply = "Sure! Here you go:\n\n```tape\n#{tape}```\n\nRun it with btape.\n"

    expect(described_class.new(client: client(reply)).call('record the home page')).to eq(tape)
  end

  it 'sends the description, and any context, as the first thing the model reads' do
    fake = client(tape)

    described_class.new(client: fake).call('record the home page', context: 'the button is #go')

    user = fake.conversations.first.last
    expect(user[:role]).to eq('user')
    expect(user[:content]).to include('record the home page').and include('#go')
  end

  it 'sends a tape that does not parse back with the reason' do
    broken = "Output demo.gif\nNavigate http://localhost:3000\n"
    fake = client(broken, tape)

    expect(described_class.new(client: fake).call('record the home page')).to eq(tape)
    repair = fake.conversations.last.last
    expect(repair[:content]).to include('line 2').and include('Navigate')
  end

  it 'sends a tape with no Output back rather than letting the recording fail on it' do
    fake = client("Goto http://localhost:3000\n", tape)

    expect(described_class.new(client: fake).call('record the home page')).to eq(tape)
    expect(fake.conversations.last.last[:content]).to include('Output')
  end

  it 'gives up after the attempts it was allowed, saying what was still wrong' do
    broken = "Output demo.gif\nNavigate http://localhost:3000\n"
    fake = client(broken, broken)

    expect { described_class.new(client: fake, attempts: 2).call('record it') }
      .to raise_error(Btape::LLM::Error, /after 2 attempts.*Navigate/m)
    expect(fake.conversations.length).to eq(2)
  end

  it 'refuses to ask about nothing' do
    expect { described_class.new(client: client(tape)).call('   ') }
      .to raise_error(Btape::LLM::Error, /nothing was said/)
  end

  # The model is told about the language by reading it out of Parser and
  # Settings, so a command or a setting added to btape is one it hears about.
  it 'describes the language it is asking for from the parser and the settings' do
    system = Btape::LLM::Prompt.system

    expect(system).to include('WaitForJS JAVASCRIPT [TIMEOUT]').and include('Set Quantizer <adaptive|rgb332>')
    Btape::Parser::SIGNATURES.each { |name, arguments| expect(system).to include("#{name} #{arguments}".strip) }
    Btape::Settings::DEFINITIONS.each_key { |name| expect(system).to include("Set #{name} <") }
  end

  # A default is quoted to the model as a tape would have to write it: the
  # seconds Settings holds are not something the parser accepts back.
  it 'quotes duration defaults as durations' do
    expect(Btape::LLM::Prompt.system).to include('100ms by default').and include('120s by default')
  end
end
