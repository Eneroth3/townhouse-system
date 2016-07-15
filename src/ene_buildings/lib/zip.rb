# Rubyzip-1.2.0 modified to be included in EneBuildings namespace to
# avoid collisions.
# Modifications are:
# - This comment.
# - Wrapping all files in own module.
# - Changing require calls within rubyzip to have full paths.
#     This should allow the files to be loaded even in another file with the
#     same basenme is already loaded.
# - Channing ::Zip to Zip.

module EneBuildings


require "delegate"
require "singleton"
require "tempfile"
require "tmpdir"
require "fileutils"
require "stringio"
require "zlib"
Sketchup.require "#{PLUGIN_DIR}/lib/zip/dos_time"
Sketchup.require "#{PLUGIN_DIR}/lib/zip/ioextras"
require "rbconfig"
Sketchup.require "#{PLUGIN_DIR}/lib/zip/entry"
Sketchup.require "#{PLUGIN_DIR}/lib/zip/extra_field"
Sketchup.require "#{PLUGIN_DIR}/lib/zip/entry_set"
Sketchup.require "#{PLUGIN_DIR}/lib/zip/central_directory"
Sketchup.require "#{PLUGIN_DIR}/lib/zip/file"
Sketchup.require "#{PLUGIN_DIR}/lib/zip/input_stream"
Sketchup.require "#{PLUGIN_DIR}/lib/zip/output_stream"
Sketchup.require "#{PLUGIN_DIR}/lib/zip/decompressor"
Sketchup.require "#{PLUGIN_DIR}/lib/zip/compressor"
Sketchup.require "#{PLUGIN_DIR}/lib/zip/null_decompressor"
Sketchup.require "#{PLUGIN_DIR}/lib/zip/null_compressor"
Sketchup.require "#{PLUGIN_DIR}/lib/zip/null_input_stream"
Sketchup.require "#{PLUGIN_DIR}/lib/zip/pass_thru_compressor"
Sketchup.require "#{PLUGIN_DIR}/lib/zip/pass_thru_decompressor"
Sketchup.require "#{PLUGIN_DIR}/lib/zip/crypto/encryption"
Sketchup.require "#{PLUGIN_DIR}/lib/zip/crypto/null_encryption"
Sketchup.require "#{PLUGIN_DIR}/lib/zip/crypto/traditional_encryption"
Sketchup.require "#{PLUGIN_DIR}/lib/zip/inflater"
Sketchup.require "#{PLUGIN_DIR}/lib/zip/deflater"
Sketchup.require "#{PLUGIN_DIR}/lib/zip/streamable_stream"
Sketchup.require "#{PLUGIN_DIR}/lib/zip/streamable_directory"
Sketchup.require "#{PLUGIN_DIR}/lib/zip/constants"
Sketchup.require "#{PLUGIN_DIR}/lib/zip/errors"

module Zip
  extend self
  attr_accessor :unicode_names, :on_exists_proc, :continue_on_exists_proc, :sort_entries, :default_compression, :write_zip64_support, :warn_invalid_date, :case_insensitive_match

  def reset!
    @_ran_once = false
    @unicode_names = false
    @on_exists_proc = false
    @continue_on_exists_proc = false
    @sort_entries = false
    @default_compression = ::Zlib::DEFAULT_COMPRESSION
    @write_zip64_support = false
    @warn_invalid_date = true
    @case_insensitive_match = false
  end

  def setup
    yield self unless @_ran_once
    @_ran_once = true
  end

  reset!
end

# Copyright (C) 2002, 2003 Thomas Sondergaard
# rubyzip is free software; you can redistribute it and/or
# modify it under the terms of the ruby license.

end
