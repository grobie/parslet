# This wraps pieces of parslet definition and gives them a name. The wrapped
# piece is lazily evaluated and cached. This has two purposes: 
#     
# * Avoid infinite recursion during evaluation of the definition
# * Be able to print things by their name, not by their sometimes
#   complicated content.
#
# You don't normally use this directly, instead you should generated it by
# using the structuring method Parslet.rule.
#
class Parslet::Atoms::Entity < Parslet::Atoms::Base
  attr_reader :name, :context, :block
  def initialize(name, context, block) # :nodoc:
    super()
    
    @name = name
    @context = context
    @block = block
  end

  def try(io) # :nodoc:
    parslet.apply(io)
  end
  
  def parslet
    @parslet ||= context.instance_eval(&block).tap { |p| 
      raise_not_implemented unless p
    }
  end

  def to_s_inner(prec) # :nodoc:
    name.to_s.upcase
  end

  def error_tree # :nodoc:
    parslet.error_tree
  end
  
private 
  def raise_not_implemented # :nodoc:
    trace = caller.reject {|l| l =~ %r{#{Regexp.escape(__FILE__)}}} # blatantly stolen from dependencies.rb in activesupport
    exception = NotImplementedError.new("rule(#{name.inspect}) { ... }  returns nil. Still not implemented, but already used?")
    exception.set_backtrace(trace)
    
    raise exception
  end
end
