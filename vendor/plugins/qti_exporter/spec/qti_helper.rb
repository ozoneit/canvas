require File.dirname(__FILE__) + '/spec_helper'
unless defined? BASE_FIXTURE_DIR
  BASE_FIXTURE_DIR = File.dirname(__FILE__) + '/fixtures/'
  VISTA_FIXTURE_DIR = BASE_FIXTURE_DIR + 'bb_vista/'
  BB8_FIXTURE_DIR = BASE_FIXTURE_DIR + 'bb8/'
  BB9_FIXTURE_DIR = BASE_FIXTURE_DIR + 'bb9/'
  RESPONDUS_FIXTURE_DIR = BASE_FIXTURE_DIR + 'respondus/'
  ANGEL_FIXTURE_DIR = BASE_FIXTURE_DIR + 'angel/'
  CENGAGE_FIXTURE_DIR = BASE_FIXTURE_DIR + 'cengage/'
  D2L_FIXTURE_DIR = BASE_FIXTURE_DIR + 'd2l/'
end
require 'qti_exporter'
require 'pp'

def get_manifest_node(question, opts={})
  manifest_node = {'identifier'=>nil, 'href'=>"#{question}.xml"}
  manifest_node.stub!(:at_css).and_return(nil)
  manifest_node.stub!(:at_css).with('instructuremetadata').and_return(manifest_node)

  t = Object.new
  t.stub!(:text).and_return(opts[:title])
  manifest_node.stub!(:at_css).with('title langstring').and_return(t)

  s = Object.new
  s.stub!(:text).and_return('237.0')
  manifest_node.stub!(:at_css).with('instructurefield[name=max_score] @value').and_return(s)
  
  it = nil
  if opts[:interaction_type]
    it = Object.new
    it.stub!(:text).and_return(opts[:interaction_type])
  end
  manifest_node.stub!(:at_css).with(('interactiontype')).and_return(it)
  
  qt = nil
  if opts[:bb_question_type]
    qt = Object.new
    qt.stub!(:text).and_return(opts[:bb_question_type])
  end
  manifest_node.stub!(:at_css).with(('instructuremetadata instructurefield[name=bb_question_type] @value')).and_return(qt)

  qt = nil
  if opts[:question_type]
    qt = Object.new
    qt.stub!(:text).and_return(opts[:question_type])
  end
  manifest_node.stub!(:at_css).with(('instructuremetadata instructurefield[name=question_type] @value')).and_return(qt)
  
  bb8a = nil
  if opts[:quiz_type]
    bb8a = Object.new
    bb8a.stub!(:text).and_return(opts[:quiz_type])
  end
  manifest_node.stub!(:at_css).with(('instructurefield[name=bb8_assessment_type] @value')).and_return(bb8a)
  
  manifest_node
end

def file_as_string(*args)
  File.read File.join(args)
end

def vista_question_dir
  File.join(VISTA_FIXTURE_DIR, "questions")
end

def bb8_question_dir
  File.join(BB8_FIXTURE_DIR, "questions")
end

def bb9_question_dir
  File.join(BB9_FIXTURE_DIR, "questions")
end

def respondus_question_dir
  File.join(RESPONDUS_FIXTURE_DIR, "questions")
end

def angel_question_dir
  File.join(ANGEL_FIXTURE_DIR, "questions")
end

def cengage_question_dir
  File.join(CENGAGE_FIXTURE_DIR, "questions")
end

def d2l_question_dir
  File.join(D2L_FIXTURE_DIR, "questions")
end
