#--
# Copyright (c) 2015-2017, John Mettraux, jmettraux+flor@gmail.com
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#
# Made in Japan.
#++

require 'awesome_print' rescue nil

require 'flor'
require 'flor/unit'


module Flor::Tools

  class Shell

    def initialize

      env = ENV['FLOR_ENV'] || 'shell'
      @root = "envs/#{env}"

      prepare_home

      @unit = Flor::Unit.new("#{@root}/etc/conf.json")

      @unit.conf['unit'] = 'cli'
      #unit.hooker.add('journal', Flor::Journal)

      prepare_db
      prepare_hooks

      @hook = 'on'

      @unit.start

      @flow_path = File.join(@root, 'home/scratch.flo')
      @payload_path = File.join(@root, 'home/payload.json')
      @variables_path = File.join(@root, 'home/variables.json')

      @c = Flor.colours({})

      do_loop
    end

    attr_reader :c

    protected

    # nice print
    def np(o)
      defined?(AwesomePrint) ? ap(o) : pp(o)
    end

    def prepare_home

      home = File.join(@root, 'home')
      return unless Dir.exists?(home)

      %w[ payload.json scratch.flo variables.json ].each do |fn|

        hfn = File.join(home, fn); next if File.exists?(hfn)

        FileUtils.cp(hfn + '.template', hfn)
        puts ".. prepared #{hfn}"
      end
    end

    def prepare_db

      @unit.storage.delete_tables if @unit.conf['sto_uri'].match(/memory/)
      @unit.storage.migrate unless @unit.storage.ready?
    end

    def prepare_hooks

      @unit.hook do |message|

        if @hook == 'off'

          # do nothing

        elsif ! message['consumed']

          # do nothing

        elsif %w[ terminated failed ].include?(message['point'])

          sleep 0.4 # let eventual debug print its stuff

          message['payload'] = message.delete('payload')
          message['consumed'] = message.delete('consumed')
            # reorganize to make payload/consumed stand out

          np message
        end
      end
    end

    def prompt

      ec = @unit.executions.where(status: 'active').count
      exes = " #{@c.yl}ex#{ec}#{@c.rs}"

      ti = @unit.timers.where(status: 'active').count
      tis = ti > 0 ? " #{@c.light_gray}ti#{ti}#{@c.rs}" : ''

      ts = nil
      if Dir.exist?(File.join(@root, 'var/tasks'))
        ts = Dir[File.join(@root, 'var/tasks/**/*.json')].count
      end
      tas = ts ? " #{@c.bl}ta#{ts}#{@c.rs}" : ''

      "flor#{exes}#{tis}#{tas} > "
    end

    def do_loop

      loop do

        line = prompt_and_read

        break unless line
        next if line.strip == ''

        md = line.split(/\s/).first
        cmd = "cmd_#{md}".to_sym

        if cmd.size > 4 && methods.include?(cmd)
          begin
            send(cmd, line)
          rescue StandardError, NotImplementedError => err
            p err
            err.backtrace[0, 7].each { |l| puts "  #{l}" }
          end
        else
          puts "unknown command #{md.inspect}"
        end
      end

      $stdout.puts
    end

    #
    # command helpers

    def self.make_alias(a, b)

      define_method("hlp_#{a}") { "alias to #{b.inspect}" }
      alias_method "cmd_#{a}", "cmd_#{b}"
    end

    def fname(line, index=1); line.split(/\s+/)[index]; end
    alias arg fname

    def choose_path(line)

      b = arg(line, 2)

      case fname(line)
      when /\Av/
        @variables_path
      when /\Ap/
        @payload_path
      when /\At/
        Dir[File.join(@root, 'var/tasks/**/*.json')].find { |pa| pa.index(b) }
      else
        @flow_path
      end
    end

    #
    # the commands

    def hlp_launch
      %{ launches a new execution of #{@flow_path} }
    end
    def cmd_launch(line)

      flow = File.read(@flow_path)
      variables = Flor::ConfExecutor.interpret(@variables_path)
      payload = Flor::ConfExecutor.interpret(@payload_path)
      domain = 'shell'

      exid = @unit.launch(
        flow, domain: domain, vars: variables, payload: payload)

      puts "  launched #{@c.green}#{exid}#{@c.reset}"
    end
    make_alias('run', 'launch')

    def hlp_help
      %{ displays this help }
    end
    def cmd_help(line)

      puts
      puts "## available commands:"
      puts
      COMMANDS.each do |cmd|
        print "* #{@c.yellow}#{cmd}#{@c.reset}"
        if hlp = (send("hlp_#{cmd}") rescue nil); print " - #{hlp.strip}"; end
        puts
      end
      puts
    end
    make_alias('h', 'help')

    def hlp_exit
      %{ exits this repl, with the given int exit code or 0 }
    end
    def cmd_exit(line)

      exit(line.split(/\s+/)[1].to_i)
    end

    def hlp_parse
      %{ parses #{@flow_path} and displays the resulting tree }
    end
    def cmd_parse(line)

      source = File.read(@flow_path)
      tree = Flor::Lang.parse(source, nil, {})

      case arg(line)
      when 'raw' then np tree
      when 'pp' then pp tree
      when 'p' then p tree
      else Flor.print_tree(tree, '0', headers: false)
      end
    end

    def hlp_cat
      %{ outputs the content of the given file }
    end
    def cmd_cat(line)

      puts File.read(choose_path(line))
    end

    def hlp_edit
      %{ open current file for edition }
    end
    def cmd_edit(line)

      if path = choose_path(line)
        system("$EDITOR #{path}")
      else
        puts "not found"
      end
    end

    def hlp_conf
      %{ prints current unit configuration }
    end
    def cmd_conf(line)
      np @unit.conf
    end

    def hlp_t
      %{ prints the file hierarchy for #{@root} }
    end
    def cmd_t(line)
      puts
      system("tree -C #{@root}")
    end

    def hlp_tasks
      %{ lists the tasks currently under var/tasks/ }
    end
    def cmd_tasks(line)

       Dir[File.join(@root, 'var/tasks/**/*.json')]
        .each_with_index { |pa, i|
          ss = pa.split('/')
          puts "%4d #{@c.yl}%11s#{@c.rs} %50s" % [ i, ss[-2], ss[-1] ] }
    end
    make_alias('tas', 'tasks')

    def hlp_executions
      %{ lists the executions currently active }
    end
    def cmd_executions(line)

      exes = @unit.executions
      exes = exes.where(status: 'active') unless arg(line) == 'all'

      exes
        .each { |e|
          puts "%4d #{@c.yl}%42s#{@c.rs} %19sZ" %
            [ e.id, e.exid, e.ctime[0, 19] ] }
      puts "#{exes.count} execution#{exes.count > 1 ? 's' : ''}."
    end
    make_alias('exes', 'executions')

    def hlp_timers
      %{ list the timers currently active }
    end
    def cmd_timers(line)

      tis = @unit.timers
      tis = tis.where(status: 'active') unless arg(line) == 'all'

      #ap tis.all
      tis
        .each_with_index { |t, i|
          puts(
            "%4d %14s #{@c.yl}%-42s#{@c.rs} %5s %-10s next:%19sZ" %
            [ t.id, t.nid, t.exid, t.type, t.schedule, t.ntime[0, 19] ]) }
      puts "#{tis.count} timer#{tis.count > 1 ? 's' : ''}."
    end
    make_alias('tis', 'timers')

    def hlp_reply
      %{ replies to a task }
    end
    def cmd_reply(line)

      t = arg(line)

      unless t
        puts "please specify a task's exid-nid or a fragment of it"
        return
      end

      path = Dir[File.join(@root, 'var/tasks/**/*.json')]
        .find { |pa| pa.index(t) }

      unless path
        puts "couldn't find a task matching #{t.inspect}"
        return
      end

      m = JSON.parse(File.read(path))
      @unit.ganger.reply(m)
      FileUtils.rm(path)
    end
    make_alias('rep', 'reply')

    def hlp_debug
      %{ re-sets debug flags (`debug on` vs `debug off`) }
    end
    def cmd_debug(line)

      @unit.conf.select! { |k, v| ! k.match(/\Alog_/) }

      rest = line.match(/\A[a-z]+(\s+.+)?/)[1]
      rest = nil if rest && rest.strip == 'off'
      rest = 'stdout,dbg' if rest && rest.strip == 'on'

      @unit.conf.merge!(Flor::Conf.interpret_flor_debug(rest)) if rest
    end

    def hlp_hook
      %{ turns hook (terminated, failed) "on" or "off" }
    end
    def cmd_hook(line)

      @hook =
        case (a = arg(line))
        when 'true', 'on'
          'on'
        when 'false', 'off'
          'off'
        else
          puts "hook is #{@hook.inspect}"
          @hook
        end
    end

    #
    # use Readline if possible

    COMMANDS = self.allocate.methods \
      .select { |m| m.to_s.match(/^cmd_/) }.collect { |m| m[4..-1] }.sort

    begin
      require 'readline'
      def prompt_and_read
        Readline.readline(prompt, true)
      end
      Readline.completion_proc =
        proc { |s|
          r = /^#{Regexp.escape(s)}/
          COMMANDS.grep(r) + Dir["#{s}*"].grep(r)
        }
      #Readline.completion_append_character =
      #  " "
    rescue LoadError => le
      def prompt_and_read
        print(prompt)
        ($stdin.readline rescue false)
      end
    end
  end
end

