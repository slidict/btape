# frozen_string_literal: true

module Btape
  # What a run produced. Callers that only want the GIF read `output_path`;
  # callers that want the frames themselves (to attach a still somewhere, say)
  # pass `frames_directory:` to Runner#run and read `frame_paths`.
  #
  # Without a `frames_directory:` the frames live in a temporary directory
  # that is removed as the run unwinds, so `frame_paths` and `named_frames`
  # are empty rather than lists of paths that no longer exist. `frame_count`
  # is always the number of frames that went into the GIF.
  #
  # `named_frames` maps the name a `Screenshot NAME` command gave a frame to
  # its path, for picking one particular frame out of a run.
  Result = Struct.new(:output_path, :frame_paths, :named_frames, :frame_count, :width, :height, keyword_init: true)
end
