
class Flor::Pro::Obj < Flor::Procedure
  #
  # "_obj" is the procedure behind objects (maps).
  #
  # Writing
  # ```
  # { a: 1, b: 2 }
  # ```
  # is in fact read as
  # ```
  # _obj
  #   'a'
  #   1
  #   'b'
  #   2
  # ```
  # by flor.

  name '_obj'

  def pre_execute

    @node['rets'] = []
    @node['atts'] = []
  end

  def execute_child(index=0, sub=nil, h=nil)

    return wrap_reply('ret' => {}) if children == 0

    return super if @node['rets'].size.odd?

    ct = children[index]
    q = (att('quote') == 'keys')

    return super unless ct[1] == [] && (deref(ct[0]) == nil || q)

    t = tree
    t[1][index] = [ '_sqs', ct[0], *ct[2..-1] ]
    @node['tree'] = t

    super
  end

  def receive_last

    payload['ret'] = @node['rets']
      .each_slice(2)
      .inject({}) { |h, (k, v)| h[k.to_s] = v; h }

    wrap_reply
  end
end

