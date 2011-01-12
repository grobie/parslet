# Matches a string of characters. 
#
# Example: 
# 
#   str('foo') # matches 'foo'
#
class Parslet::Atoms::Str < Parslet::Atoms::Base
  attr_reader :str
  def initialize(str)
    @str = str
  end
  
  def to_s_inner(prec) # :nodoc:
    "'#{str}'"
  end
end

