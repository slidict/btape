# frozen_string_literal: true

require_relative '../parser'
require_relative '../settings'

module Btape
  module LLM
    # What the model is told before it is asked for a tape.
    #
    # The command list and the settings table are built from Parser and
    # Settings rather than written out again here, so a command added to the
    # language is a command the model is told about, and a setting cannot be
    # described to it with a default it no longer has.
    module Prompt
      RULES = [
        'Answer with the contents of a .tape file and nothing else: no explanation, no code fences.',
        'The script must contain exactly one Output line, naming a .gif file, and it comes first.',
        'One command per line. Lines starting with # are comments.',
        'The line is split like a shell command, so any argument containing a space must be quoted ' \
        'with double quotes.',
        'Click, WaitFor and Frame take a CSS selector, or text=Some text to match on visible text.',
        'Durations are a number followed by ms or s, such as 500ms or 1.5s.',
        'Prefer WaitFor or WaitForJS over Sleep for anything the page has to finish doing; ' \
        'Sleep is for holding a finished frame on screen long enough to be seen.',
        'Use only the commands and settings listed above. Do not invent either, ' \
        'and do not use a shell, a comment or a blank line to stand in for one.'
      ].freeze

      EXAMPLE = <<~TAPE
        # Signing in, recorded at half size
        Output signin.gif
        Viewport 1280x720
        Set Scale 0.5

        Goto http://localhost:3000/signin
        WaitFor "#email"
        Type "#email" "demo@example.com"
        Type "#password" "correct horse"
        Click "text=Sign in"
        WaitFor "text=Welcome back" 5s
        Sleep 2s
      TAPE

      # What a setting takes, as the coercions in Settings enforce it. A
      # default is shown as a tape would have to write it rather than as
      # Settings holds it, since `Set FrameDelay 0.1` is not something the
      # parser would accept back.
      VALUES = {
        duration: 'a duration',
        url: "a #{Settings::URL_SCHEMES.join(', ')} url",
        count: 'a whole number, 0 or more',
        positive_integer: 'a whole number, 1 or more',
        positive_float: 'a number'
      }.freeze

      module_function

      def system
        <<~PROMPT
          You write btape scripts. btape runs a .tape file against Chromium and records
          the run as an animated GIF, so a tape is a short, deliberate demonstration
          rather than a test: it moves at a pace somebody can watch.

          The commands, one per line:

          #{indent(commands)}

          A run is configured with `Set NAME VALUE`:

          #{indent(settings)}

          Rules:

          #{indent(RULES.map { |rule| "- #{rule}" }.join("\n"))}

          An example of a whole tape:

          #{indent(EXAMPLE)}
        PROMPT
      end

      def user(description, context: nil)
        return description if context.nil? || context.strip.empty?

        <<~PROMPT
          #{description}

          Context about the page being recorded — prefer the selectors it names over
          any you would otherwise guess at:

          #{context}
        PROMPT
      end

      # A tape that did not parse goes back with the parser's own complaint,
      # which names the line and what was wrong with it. Saying so beats
      # asking again and hoping, since the model can see what it wrote.
      def repair(reason)
        <<~PROMPT
          btape rejected that tape: #{reason}

          Answer with the whole corrected tape, and nothing else.
        PROMPT
      end

      def commands
        Parser::SIGNATURES.map { |name, arguments| "#{name} #{arguments}".strip }.join("\n")
      end

      def settings
        Settings::DEFINITIONS.map do |name, (_attribute, coercion, default)|
          takes = coercion.is_a?(Array) ? coercion.join('|') : VALUES.fetch(coercion)
          "Set #{name} <#{takes}>#{" — #{literal(coercion, default)} by default" unless default.nil?}"
        end.join("\n")
      end

      # A coerced default as a tape would write it: durations are held in
      # seconds and go back to the ms or s they were read from.
      def literal(coercion, default)
        return default.to_s unless coercion == :duration
        return "#{(default * 1000).round}ms" if default < 1

        "#{default.to_i == default ? default.to_i : default}s"
      end

      # Blank lines are left alone, so that indenting a block into the prompt
      # does not leave trailing whitespace through the middle of it.
      def indent(text)
        text.strip.gsub(/^(?=.)/, '  ')
      end
    end
  end
end
