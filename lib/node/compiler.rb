# Copyright (c) 2016 Node.js Compiler contributors
# 
# This file is part of Node.js Compiler, distributed under the MIT License
# For full terms see the included LICENSE file

require "node/compiler/constants"
require "node/compiler/error"
require "node/compiler/utils"
require "node/compiler/test"
require "node/compiler/npm"
require 'shellwords'
require 'tmpdir'
require 'fileutils'
require 'json'
require 'open3'

module Node
  class Compiler
    def initialize(entrance, options = {})
      @entrance = entrance
      @options = options

      init_entrance
      init_options
    end

    def init_entrance
      # Important to expand_path; otherwiser the while would not be right
      @entrance = File.expand_path(@entrance)
      raise Error, "Cannot find entrance #{@entrance}." unless File.exist?(@entrance)
      if @options[:project_root]
        @project_root = File.expand_path(@options[:project_root])
      else
        @project_root = File.dirname(@entrance)
        # this while has to correspond with the expand_path above
        while !File.exist?(File.expand_path('./package.json', @project_root))
          break if '/' == @project_root
          @project_root = File.expand_path('..', @project_root)
        end
      end
      unless File.exist?(File.expand_path('./package.json', @project_root))
        raise Error, "Cannot find a package.json at the project root #{@project_root}"
      end
    end

    def init_options
      if Gem.win_platform?
        @options[:output] ||= 'a.exe'
      else
        @options[:output] ||= 'a.out'
      end
      @options[:output] = File.expand_path(@options[:output])

      @options[:tempdir] ||= '/tmp/nodec'
      @options[:tempdir] = File.expand_path(@options[:tempdir])
      if @options[:tempdir].include? @project_root
        raise Error, "tempdir #{@options[:tempdir]} cannot reside inside the project root #{@project_root}."
      end

      Utils.prepare_tempdir(@options[:tempdir])
      @vendor_node = File.join(@options[:tempdir], NODE_VERSION)
    end

    def run!
      @copy_dir = Utils.inject_memfs(@project_root, @vendor_node)
      inject_entrance
      Gem.win_platform? ? compile_win : compile
    end

    def inject_entrance
      target = File.expand_path('./lib/enclose_io_entrance.js', @vendor_node)
      path = mempath @entrance
      File.open(target, "w") { |f| f.puts %Q`module.exports = "#{path}";` }
      # remove shebang
      lines = File.read(@entrance).lines
      lines[0] = "// #{lines[0]}" if '#!' == lines[0][0..1]
      File.open(copypath(@entrance), "w") { |f| f.print lines.join }
    end

    def compile_win
      Utils.chdir(@vendor_node) do
        Utils.run("call vcbuild.bat #{@options[:vcbuild_args]}")
      end
      STDERR.puts "-> FileUtils.cp(#{File.join(@vendor_node, 'Release\\node.exe')}, #{@options[:output]})"
      FileUtils.cp(File.join(@vendor_node, 'Release\\node.exe'), @options[:output])
    end

    def compile
      Utils.chdir(@vendor_node) do
        Utils.run("./configure")
        Utils.run("make #{@options[:make_args]}")
      end
      STDERR.puts "-> FileUtils.cp(#{File.join(@vendor_node, 'out/Release/node')}, #{@options[:output]})"
      FileUtils.cp(File.join(@vendor_node, 'out/Release/node'), @options[:output])
    end

    def mempath(path)
      path = File.expand_path(path)
      raise 'Logic error in mempath' unless @project_root == path[0...(@project_root.size)]
      "#{MEMFS}#{path[(@project_root.size)..-1]}"
    end

    def copypath(path)
      path = File.expand_path(path)
      raise 'Logic error 1 in copypath' unless @project_root == path[0...(@project_root.size)]
      ret = File.join(@copy_dir, path[(@project_root.size)..-1])
      raise 'Logic error 2 in copypath' unless File.exist?(ret)
      ret
    end
  end
end