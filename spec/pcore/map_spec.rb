
#
# specifying flor
#
# Mon Mar 28 16:35:30 JST 2016
#

require 'spec_helper'


describe 'Flor procedures' do

  before :each do

    @executor = Flor::TransientExecutor.new
  end

  describe 'map' do

    it 'maps elements' do

      r = @executor.launch(
        %q{
          map [ 1, 2, 3 ]
            def x
              + x 3
        })

      expect(r['point']).to eq('terminated')
      expect(r['payload']['ret']).to eq([ 4, 5, 6 ])
    end

    it 'maps f.ret by default' do

      r = @executor.launch(
        %q{
          [ 1, 2, 3 ]
          map
            def x
              + x 2
        })

      expect(r['point']).to eq('terminated')
      expect(r['payload']['ret']).to eq([ 3, 4, 5 ])
    end

    it 'maps to a function by its name' do

      r = @executor.launch(
        %q{
          define add3 x
            + x 3
          map [ 0, 1 ] add3
        })

      expect(r['point']).to eq('terminated')
      expect(r['payload']['ret']).to eq([ 3, 4 ])
    end

    it 'does not let att get in the way of col and fun' do

      r = @executor.launch(
        %q{
          map [ 0, 1, 2 ], tag: 'y'
            def x \ + x 3
        })

      expect(r['point']).to eq('terminated')
      expect(r['payload']['ret']).to eq([ 3, 4, 5 ])
    end

    it 'has its own vars' do

      r = @executor.launch(
        %q{
          sequence
            map [ 0, 1, 2 ]
              set a 1
              def x
                set a
                  + a 1
                + x a
        })

      expect(r['point']).to eq('terminated')
      expect(r['payload']['ret']).to eq([ 2, 4, 6 ])
      expect(r['vars']).to eq({})
    end

    it 'shows the index via vars' do

      r = @executor.launch(
        %q{
          map [ 'a', 'b' ]
            def x \ idx
        })

      expect(r['point']).to eq('terminated')
      expect(r['payload']['ret']).to eq([ 0, 1 ])
    end

    it 'maps thanks to the last fun in the block' do

      r = @executor.launch(
        %q{
          map [ 0, 1 ]
            define sum x
              set y (+ y 1)
              + x y
            set y 2
            sum
        })

      expect(r['point']).to eq('terminated')
      expect(r['payload']['ret']).to eq([ 3, 5 ])
    end

    it 'maps thanks to the last fun in the block' do

      r = @executor.launch(
        %q{
          map [ 0, 1 ]
            set y 1
            def x
              set y (+ y 1)
              + x y
        })

      expect(r['point']).to eq('terminated')
      expect(r['payload']['ret']).to eq([ 2, 4 ])
    end

    it "keeps the given 'vars' hash" do

      r = @executor.launch(
        %q{
          map a \ def i \ * 7 i
        },
        vars: { 'a' => (0..7).to_a })

      expect(r['point']).to eq('terminated')
      expect(r['payload']['ret']).to eq([ 0, 7, 14, 21, 28, 35, 42, 49 ])
    end
  end

  describe 'for-each' do

    it 'iterates over each element' do

      r = @executor.launch(
        %q{
          set l []
          for-each [ 0 1 2 3 4 5 6 7 ]
            def x
              pushr l (2 * x) if x % 2 == 0
        })

      expect(r['point']).to eq('terminated')
      expect(r['vars']).to eq({ 'l' => [ 0, 4, 8, 12 ] })
      expect(r['payload']['ret']).to eq(12)
    end
  end
end

