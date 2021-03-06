
#
# specifying flor
#
# Thu Jan  5 07:17:48 JST 2017  Ishinomaki
#

require 'spec_helper'


describe 'Flor punit' do

  before :each do

    @unit = Flor::Unit.new('envs/test/etc/conf.json')
    @unit.conf[:unit] = 'pu_schedule'
    @unit.hooker.add('journal', Flor::Journal)
    @unit.storage.delete_tables
    @unit.storage.migrate
    @unit.start
  end

  after :each do

    @unit.shutdown
  end

  describe 'schedule' do

    it 'creates a timer' do

      flor = %q{
        schedule cron: '0 0 1 jan *'
          def msg \ alpha
        stall _
      }

      r = @unit.launch(flor, wait: 'end')
      exid = r['exid']

      # check execution

      exe = @unit.executions[exid: exid]

      expect(exe).not_to eq(nil)
      expect(exe.status).to eq('active')
      expect(exe.failed?).to eq(false)

      # check timer

      expect(@unit.timers.count).to eq(1)

      t = @unit.timers.first

      expect(t.exid).to eq(exid)
      expect(t.type).to eq('cron')
      expect(t.schedule).to eq('0 0 1 jan *')
      expect(t.ntime_t.localtime.year).to eq(Time.now.utc.year + 1)

      td = t.data

      expect(td['message']['point']).to eq('execute')
      expect(td['message']['tree'][0]).to eq('_apply')

      # check nodes 0 still knows 0_0, 0_0 is flanking 0

      n_0 = exe.nodes['0']

      expect(n_0['status'].last['status']).to eq(nil) # open
      expect(n_0['cnodes']).to eq(%w[ 0_0 0_1 ]) # 0_0 is flanking

      n_0_0 = exe.nodes['0_0']

      expect(n_0_0['status'].last['status']).to eq(nil) # open
      expect(n_0_0['parent']).to eq('0')
      expect(n_0_0['noreply']).to eq(true) # since it's flanking
    end

    it 'triggers' do

      flor = %q{
        schedule cron: '* * * * * *'
          def msg \ 1
        stall _
      }

      r = @unit.launch(flor, wait: 'trigger')

      expect(r['point']).to eq('trigger')
      expect(r['m']).to eq(16)
      expect(r['sm']).to eq(11) # the 'schedule' message
    end

    it 'behaves correctly as root node' do

      flor = %q{
        schedule cron: '0 0 1 jan *'
          def msg \ alpha
      }

      r = @unit.launch(flor, wait: 'end')
      exid = r['exid']

      # check execution

      exe = @unit.executions[exid: exid]

      expect(exe).not_to eq(nil)
      expect(exe.status).to eq('active')
      expect(exe.failed?).to eq(false)
      expect(exe.nodes.keys).to eq(%w[ 0 ])

      # check nodes 0 still knows 0_0, 0_0 is flanking 0

      n_0 = exe.nodes['0']

      expect(n_0['status'].last['status']).to eq(nil) # open

      # check journal

      j = @unit.journal

      expect(j).not_to include_msg(point: 'terminated')

      # check timer

      expect(@unit.timers.count).to eq(1)

      t = @unit.timers.first

      expect(t.exid).to eq(exid)
      expect(t.type).to eq('cron')
      expect(t.schedule).to eq('0 0 1 jan *')
      expect(t.ntime_t.localtime.year).to eq(Time.now.utc.year + 1)

      td = t.data

      expect(td['message']['point']).to eq('execute')
      expect(td['message']['tree'][0]).to eq('_apply')

      #
      # cancel and verify it terminates correctly

      @unit.cancel(exid: exid, nid: '0')

      r = @unit.wait(exid, 'terminated')

      sleep 0.350

      expect(
        @unit.journal.select { |m| m['point'] == 'terminated' }.count
      ).to eq(
        1
      )

      exe = @unit.executions[exid: exid]

      expect(exe).not_to eq(nil)
      expect(exe.status).to eq('terminated')
      expect(exe.failed?).to eq(false)
      expect(exe.nodes.keys).to eq(%w[ 0 ])
    end

    it 'does not cancel its children' do

      flor = %q{
        schedule cron: '* * * * * *'
          def msg \ stall _
        stall _
      }

      exid = @unit.launch(flor)

      3.times { @unit.wait(exid, 'end') }

      exe = @unit.executions[exid: exid]

      expect(
        exe.nodes.keys
      ).to eq(%w[
        0 0_0 0_1 0_0_1-1 0_0_1_1-1 0_0_1-2 0_0_1_1-2
      ])

      @unit.cancel(exid: exid, nid: '0_0')

      @unit.wait(exid, 'ceased; end')

      exe = @unit.executions[exid: exid]

      expect(
        exe.nodes.keys
      ).to eq(%w[
        0 0_1 0_0_1-1 0_0_1_1-1 0_0_1-2 0_0_1_1-2
      ])
    end

    context 'cron' do

      it 'triggers repeatedly' do

        @unit.launch(
          %q{
            set count 0
            schedule cron: '* * * * * *' # every second
              def msg
                set count (+ count 1)
            stall _
          },
          wait: [ '0_1 trigger' ] * 4,
          timeout: 9)

        sleep 0.350

        t = @unit.timers.first
        ms = Flor.dup(@unit.journal)

        tms = ms.select { |m| m['point'] == 'trigger' }
        seconds = tms.collect { |m| Fugit.parse(m['consumed']).sec }

        expect(tms.size).to eq(4)

        expect(t.schedule).to eq('* * * * * *')
        expect(t.count).to eq(4)

        ss = (seconds.first..seconds.first + 3)
          .collect { |s| s % 60 }

        expect(seconds).to eq(ss)
      end
    end

    context 'upon cancellation' do

      it 'cancels itself but not its children' do

        flor = %{
          schedule cron: '* * * * * *' # every second
            def msg
              hole _
          stall _
        }

        r = @unit.launch(flor, wait: 'task')

        exid = r['exid']

        @unit.cancel(exid: r['exid'], nid: '0')

        @unit.wait(exid, 'end'); sleep 0.777

        j = @unit.journal
#puts Flor.to_s(j)
#pp j
        expect(j).to include_msg(point: 'terminated')
        expect(j).to include_msg(point: 'trigger', nid: '0_0')
        expect(j).to include_msg(point: 'ceased', from: '0_0')
        expect(j).not_to include_msg(point: 'detask')

        expect(@unit.timers.count).to eq(0)

        exe = @unit.executions[exid: exid]

        expect(
          exe.nodes.keys
        ).to eq(%w[
          0 0_0_1-1 0_0_1_1-1
        ])
      end
    end
  end
end

