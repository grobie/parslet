
# Interprets a parslet tree for a given input. 
#
class Parslet::Interpreter
  attr_reader :io
  def initialize(io)
    @io = io
  end
  
  def repetition(rep)
    occ = 0
    result = [rep.tag]   # initialize the result array with the tag (for flattening)
    catch(:error) {
      result << rep.parslet.apply(io, self)
      occ += 1
      
      # If we're not greedy (max is defined), check if that has been 
      # reached. 
      return result if rep.max && occ>=rep.max
      redo
    }
    
    # Greedy matcher has produced a failure. Check if occ (which will
    # contain the number of sucesses) is in {min, max}.
    # p [:repetition, occ, min, max]
    rep.error(io, "Expected at least #{rep.min} of #{rep.parslet.inspect}") if occ < rep.min
    return result
  end
  
  def sequence(sequence)
    catch(:error) {
      return [:sequence]+sequence.parslets.map { |p| 
        # Save each parslet as potentially offending (raising an error). 
        @offending_parslet = p
        p.apply(io, self) 
      }
    }

    sequence.error(io, "Failed to match sequence (#{sequence.inspect})")
  end
  
  def alternative(alternative)
    alternative.alternatives.each { |a|
      catch(:error) {
        return a.apply(io, self)
      }
    }
    # If we reach this point, all alternatives have failed. 
    alternative.error(io, "Expected one of #{alternative.alternatives.inspect}.")
  end
  
  def lookahead(lookahead)
    pos = io.pos

    failed = true
    catch(:error) {
      lookahead.bound_parslet.apply(io, self)
      failed = false
    }
    return failed ? lookahead.fail(io) : lookahead.success(io)

  ensure 
    io.pos = pos
  end
  
  def entity(entity)
    entity.parslet.apply(io, self)
  end
  
  def str(str)
    old_pos = io.pos
    s = io.read(str.str.size)
    str.error(io, "Premature end of input") unless s && s.size==str.str.size
    str.error(io, "Expected #{str.str.inspect}, but got #{s.inspect}", old_pos) \
      unless s==str.str
    return s
  end
  
  def re(re)
    s = io.read(1)
    re.error(io, "Premature end of input") unless s
    re.error(io, "Failed to match #{re.match.inspect[1..-2]}") unless s.match(re.re)
    return s
  end
end