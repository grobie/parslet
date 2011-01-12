# Base class for all parslets, handles orchestration of calls and implements
# a lot of the operator and chaining methods.
#
class Parslet::Atoms::Base
  include Parslet::Atoms::Precedence
  
  # Given a string or an IO object, this will attempt a parse of its contents
  # and return a result. If the parse fails, a Parslet::ParseFailed exception
  # will be thrown. 
  #
  def parse(io)
    if io.respond_to? :to_str
      io = StringIO.new(io)
    end
    
    visitor = Parslet::Interpreter.new(io)
    
    result = nil
    error_message_or_success = catch(:error) {
      result = apply(io, visitor)
      :success
    }
    
    # If we didn't succeed the parse, raise an exception for the user. 
    # Stack trace will be off, but the error tree should explain the reason
    # it failed.
    if error_message_or_success != :success
      raise Parslet::ParseFailed, error_message_or_success
    end
    
    # If we haven't consumed the input, then the pattern doesn't match. Try
    # to provide a good error message (even asking down below)
    unless io.eof?
      # Do we know why we stopped matching input? If yes, that's a good
      # error to fail with. Otherwise just report that we cannot consume the
      # input.
      if cause 
        # Don't garnish the real cause; but the exception is different anyway.
        raise Parslet::ParseFailed, 
          "Unconsumed input, maybe because of this: #{cause}"
      else
        parse_failed(
          format_cause(io, "Don't know what to do with #{io.string[io.pos,100]}"))
      end
    end
    
    return flatten(result)
  end
  
  def visit(visitor)
    visitor.send(self.class.name.split('::').last.downcase, self)
  end

  #---
  # Calls the #try method of this parslet. In case of a parse error, apply
  # leaves the io in the state it was before the attempt. 
  #+++
  def apply(io, visitor) # :nodoc:
    # p [:start, self, io.string[io.pos, 10]]
    
    old_pos = io.pos
    
    # p [:try, self, io.string[io.pos, 20]]
    message = catch(:error) {
      r = self.visit(visitor)
      # p [:return_from, self, r, flatten(r)]
      
      # This has just succeeded, so last_cause must be empty
      @last_cause = nil
      return r
    }
    
    # We only reach this point if the parse has failed. message is not nil.
    # p [:failing, self, io.string[io.pos, 20]]
    
    io.pos = old_pos
    throw :error, message
  end

  # Construct a new atom that repeats the current atom min times at least and
  # at most max times. max can be nil to indicate that no maximum is present. 
  #
  # Example: 
  #   # match any number of 'a's
  #   str('a').repeat     
  #
  #   # match between 1 and 3 'a's
  #   str('a').repeat(1,3)
  #
  def repeat(min=0, max=nil)
    Parslet::Atoms::Repetition.new(self, min, max)
  end
  
  # Returns a new parslet atom that is only maybe present in the input. This
  # is synonymous to calling #repeat(0,1). Generated tree value will be 
  # either nil (if atom is not present in the input) or the matched subtree. 
  #
  # Example: 
  #   str('foo').maybe
  #
  def maybe
    Parslet::Atoms::Repetition.new(self, 0, 1, :maybe)
  end

  # Chains two parslet atoms together as a sequence. 
  #
  # Example: 
  #   str('a') >> str('b')
  #
  def >>(parslet)
    Parslet::Atoms::Sequence.new(self, parslet)
  end

  # Chains two parslet atoms together to express alternation. A match will
  # always be attempted with the parslet on the left side first. If it doesn't
  # match, the right side will be tried. 
  #
  # Example:
  #   # matches either 'a' OR 'b'
  #   str('a') | str('b')
  #
  def |(parslet)
    Parslet::Atoms::Alternative.new(self, parslet)
  end
  
  # Tests for absence of a parslet atom in the input stream without consuming
  # it. 
  # 
  # Example: 
  #   # Only proceed the parse if 'a' is absent.
  #   str('a').absnt?
  #
  def absnt?
    Parslet::Atoms::Lookahead.new(self, false)
  end

  # Tests for presence of a parslet atom in the input stream without consuming
  # it. 
  # 
  # Example: 
  #   # Only proceed the parse if 'a' is present.
  #   str('a').prsnt?
  #
  def prsnt?
    Parslet::Atoms::Lookahead.new(self, true)
  end

  # Marks a parslet atom as important for the tree output. This must be used 
  # to achieve meaningful output from the #parse method. 
  #
  # Example:
  #   str('a').as(:b) # will produce {:b => 'a'}
  #
  def as(name)
    Parslet::Atoms::Named.new(self, name)
  end

  # Takes a mixed value coming out of a parslet and converts it to a return
  # value for the user by dropping things and merging hashes. 
  #
  def flatten(value) # :nodoc:
    # Passes through everything that isn't an array of things
    return value unless value.instance_of? Array

    # Extracts the s-expression tag
    tag, *tail = value

    # Merges arrays:
    result = tail.
      map { |e| flatten(e) }            # first flatten each element
      
    case tag
      when :sequence
        return flatten_sequence(result)
      when :maybe
        return result.first
      when :repetition
        return flatten_repetition(result)
    end
    
    fail "BUG: Unknown tag #{tag.inspect}."
  end
  
  def flatten_sequence(list) # :nodoc:
    list.compact.inject('') { |r, e|        # and then merge flat elements
      merge_fold(r, e)
    }
  end
  def merge_fold(l, r) # :nodoc:
    # equal pairs: merge. 
    if l.class == r.class
      if l.is_a?(Hash)
        warn_about_duplicate_keys(l, r)
        return l.merge(r)
      else
        return l + r
      end
    end
    
    # unequal pairs: hoist to same level. 
    
    # special case: If one of them is a string, the other is more important 
    return l if r.class == String
    return r if l.class == String
    
    # otherwise just create an array for one of them to live in 
    return l + [r] if r.class == Hash
    return [l] + r if l.class == Hash
    
    fail "Unhandled case when foldr'ing sequence."
  end

  def flatten_repetition(list) # :nodoc:
    if list.any? { |e| e.instance_of?(Hash) }
      # If keyed subtrees are in the array, we'll want to discard all 
      # strings inbetween. To keep them, name them. 
      return list.select { |e| e.instance_of?(Hash) }
    end

    if list.any? { |e| e.instance_of?(Array) }
      # If any arrays are nested in this array, flatten all arrays to this
      # level. 
      return list.
        select { |e| e.instance_of?(Array) }.
        flatten(1)
    end
    
    # If there are only strings, concatenate them and return that. 
    list.inject('') { |s,e| s<<(e||'') }
  end

  def self.precedence(prec) # :nodoc:
    define_method(:precedence) { prec }
  end
  precedence BASE
  def to_s(outer_prec=OUTER) # :nodoc:
    if outer_prec < precedence
      "("+to_s_inner(precedence)+")"
    else
      to_s_inner(precedence)
    end
  end
  def inspect # :nodoc:
    to_s(OUTER)
  end

  # Cause should return the current best approximation of this parslet
  # of what went wrong with the parse. Not relevant if the parse succeeds, 
  # but needed for clever error reports. 
  #
  def cause # :nodoc:
    @last_cause
  end

  # Error tree returns what went wrong here plus what went wrong inside 
  # subexpressions as a tree. The error stored for this node will be equal
  # with #cause. 
  #
  def error_tree
    Parslet::ErrorTree.new(self) if cause?
  end
  def cause? # :nodoc:
    not @last_cause.nil?
  end

  # TODO comments!!!
  # Report/raise a parse error with the given message, printing the current
  # position as well. Appends 'at line X char Y.' to the message you give. 
  # If +pos+ is given, it is used as the real position the error happened, 
  # correcting the io's current position.
  #
  def error(io, str, pos=nil)
    @last_cause = format_cause(io, str, pos)
    throw :error, @last_cause
  end
  def parse_failed(str)
    @last_cause = str
    raise Parslet::ParseFailed,
      @last_cause
  end
  def format_cause(io, str, pos=nil)
    pre = io.string[0..(pos||io.pos)]
    lines = Array(pre.lines)
    
    return str if lines.empty?
      
    pos   = lines.last.length
    return "#{str} at line #{lines.count} char #{pos}."
  end
  def warn_about_duplicate_keys(h1, h2)
    d = h1.keys & h2.keys
    unless d.empty?
      warn "Duplicate subtrees while merging result of \n  #{self.inspect}\nonly the values"+
           " of the latter will be kept. (keys: #{d.inspect})"
    end
  end
end
