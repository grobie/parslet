# A simple xml parser. It is simple in the respect as that it doesn't address
# any of the complexities of XML. This is ruby 1.9.

$:.unshift '../lib'

require 'pp'
require 'parslet'

module XML
  include Parslet

  root :document
  
  rule(:document) {
    tag(close: false).as(:o) >> document.as(:i) >> tag(close: true).as(:c) |
    text
  }
  
  # Perhaps we could have some syntax sugar to make this more easy?
  #
  def tag(opts={})
    close = opts[:close] || false
    
    parslet = str('<')
    parslet = parslet >> str('/') if close
    parslet = parslet >> (str('>').absnt? >> match("[a-zA-Z]")).repeat(1).as(:name)
    parslet = parslet >> str('>')
    
    parslet
  end
  
  rule(:text) {
    match('[^<>]').repeat(0)
  }
end

def check(xml)
  include XML
  r=parse(xml)

  # We'll validate the tree by reducing valid pairs of tags into simply the
  # string "verified". If the transformation ends on a string, then the
  # document was 'valid'. 
  #
  t = Parslet::Transform.new do
    rule(
      o: {name: simple(:tag)}, 
      c: {name: simple(:tag)}, 
      i: simple(:t)
    ) { 'verified' } 
  end

  t.apply(r)
end

pp check("<a><b>some text in the tags</b></a>")
pp check("<b><b>some text in the tags</b></a>")