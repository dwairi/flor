
#
# specifying flor
#
# Sat Jan  9 07:20:32 JST 2016
#

require 'spec_helper'


describe 'Flor procedures' do

  before :each do

    @executor = Flor::TransientExecutor.new
  end

  describe 'sequence' do

    it 'returns immediately if empty' do

      flor = %{
        sequence _
      }

      r = @executor.launch(flor)

      expect(r['point']).to eq('terminated')
      expect(r['payload']).to eq({})
    end

    it 'chains children' do

      flor = %{
        sequence
          set f.a
            0
          set f.b
            1
      }

      r = @executor.launch(flor)

      expect(r['point']).to eq('terminated')
      expect(r['payload']).to eq({ 'a' => 0, 'b' => 1, 'ret' => nil })
    end

    it 'returns the value of last child as $(ret)' do

      flor = %{
        sequence
          1
          2
      }

      r = @executor.launch(flor)

      expect(r['point']).to eq('terminated')
      expect(r['payload']).to eq({ 'ret' => 2 })
    end

    it 'keeps track of its children' do

      flor = %{
        sequence
          0
          stall _
      }

      r = @executor.launch(flor)

      expect(r).to eq(nil)

      n = @executor.execution['nodes']['0']

      expect(n['cnodes']).to eq(%w[ 0_1 ])
    end
  end
end

