#!/usr/bin/env ruby
require 'optparse'
require 'bundler/setup'
require 'mini_magick'
require 'pry'

module Slascii
  class CLI
    attr_reader :output

    # Darker to lighter
    PALETTES = {
      ascii: ['00', '33', 'oo', '++', '--', '  '].freeze,
      unicode: ['██', '▓▓', '▒▒', '  '].freeze,
      shopify:  [':s33:', ':s13:', ':s12:', ':s11:', ':s02:', ':s00:'].freeze,
      ping_pong: [':pong:', ':s00:'].freeze,
      troll: [':troll:', '  '].freeze,
      madmatt: [':madmatt:', ':s00:'].freeze,
    }.freeze

    def run
      ### Program EntryPoint ###
      options = parse_options

      palette = options[:palette]
      palette = palette.reverse if options[:invert]

      @banner = options.fetch(:banner, true)
      @output = if options[:chars]
        make_art_to_character_count(options[:filename], palette, options[:chars])
      else
        make_art_to_width(options[:filename], palette, options[:width])
      end
    end

    def write_output
      puts output
      puts "\n\n(#{output.length} chars)" if @banner
    end

    private

    def verbose?
      @verbose == true
    end

    def vlog(message)
      puts message if verbose?
    end

    def parse_options
      options = {}

      parser = OptionParser.new do |opts|
        opts.banner = "Usage: thumbs.rb [options] FILE_NAME"

        opts.on('-c', '--chars C', 'Specify the number of characters to use (default 4000, Slack message limit)') do |c|
          options[:chars] = c.to_i
        end

        opts.on('-w', '--width N', 'Specify width of output (overrides --chars)') do |n|
          options[:width] = n.to_i
        end

        opts.on '-p', '--palette P', "Specify character palette to use: #{PALETTES.keys.join(', ')}" do |p|
          unless (options[:palette] = PALETTES[p.to_sym])
            puts "Invalid palette: #{p}"
            puts "Available palettes:"
            PALETTES.keys.each { |k| puts "  - #{k}" }
            exit
          end
        end

        opts.on '-b', '--no-banner', 'Do not print the character count below the output' do
          options[:banner] = false
        end

        opts.on '-i', '--invert', 'Invert colors' do
          options[:invert] = true
        end

        opts.on '-v', '--verbose', 'Debugging output' do
          @verbose = true
        end
      end

      parser.parse!

      options[:filename] = ARGV.pop

      raise 'Width must be greater than 1' if options[:width] && options[:width] < 1
      raise 'Missing filename' unless options[:filename]
      raise 'Cannot specify both --chars and --width' if options[:chars] && options[:width]

      options[:chars] = 4000 if options[:chars].nil? && options[:width].nil?
      options[:palette] ||= PALETTES.values.first

      options
    rescue StandardError => ex
      puts "Error: #{ex.message}\n\n#{parser}"
      exit(1)
    end

    def open_image(path)
      MiniMagick::Image.open(path)
    rescue StandardError => ex
      puts "Unable to open #{path}: #{ex.message}"
      exit(1)
    end

    def make_art_to_character_count(path, palette, count)
      vlog "Generating output to #{count} character limit"

      maps = Hash.new do |hash, width|
        output = make_art_to_width(path, palette, width)
        vlog "Trying #{width}: #{output.length} characters"
        hash[width] = output
      end

      # Find the lower bound
      lower = 40.downto(1).find do |bound|
        maps[bound].length <= count
      end

      # Starting from the lower bound, find the first width N that exceeds the character limit, then return map[N - 1]
      lower.upto(Float::INFINITY).find do |n|
        return maps[n] if maps[n + 1].length > count
      end
    end

    def make_art_to_width(path, palette, width)
      img = open_image(path)
      img.colorspace 'Gray'

      img.resize "#{width}x10000"

      # Turn the 2d array of [r, g, b] values into a 2d array of [r] values (r == g == b because grayscale)
      pixels = img.get_pixels.map { |row| row.map(&:first) }

      # Find the grayscale limits of the photo so we can map only the used range to our palette, which
      # is probably much smaller than the full 255 grayscale values

      (darkest, lightest) = pixels.flatten.minmax

      range = lightest - darkest

      # The gap between each palette value
      step = range.fdiv(palette.size - 1)

      pixels.map do |row|
        row.map do |pixel|
          palette.fetch(((pixel - darkest) / step).round)
        end.join
      end.join("\n")
    end
  end
end
