require File.dirname(__FILE__) + '/../../qti_helper'

describe "Converting Blackboard 8 qti" do

  it "should convert multiple choice" do
    manifest_node=get_manifest_node('multiple_choice', :interaction_type => 'choiceInteraction', :bb_question_type => 'Multiple Choice')
    hash = Qti::ChoiceInteraction.create_instructure_question(:manifest_node=>manifest_node, :base_dir=>bb8_question_dir)
    hash[:answers].each {|a|a.delete(:id)}
    hash.should == BB8Expected::MULTIPLE_CHOICE
  end

  it "should convert multiple choice" do
    manifest_node=get_manifest_node('multiple_choice_blank_answers', :interaction_type => 'choiceInteraction', :bb_question_type => 'Multiple Choice')
    hash = Qti::ChoiceInteraction.create_instructure_question(:manifest_node=>manifest_node, :base_dir=>bb8_question_dir)
    hash[:answers].each {|a|a.delete(:id)}
    hash.should == BB8Expected::MULTIPLE_CHOICE_BLANK_ANSWERS
  end

  it "should convert either/or (yes/no) into multiple choice" do
    manifest_node=get_manifest_node('either_or_yes_no', :interaction_type => 'choiceInteraction', :bb_question_type => 'Either/Or')
    hash = Qti::ChoiceInteraction.create_instructure_question(:manifest_node=>manifest_node, :base_dir=>bb8_question_dir)
    hash[:answers].each {|a|a.delete(:id)}
    hash.should == BB8Expected::EITHER_OR_YES_NO
  end

  it "should convert either/or (agree/disagree) into multiple choice" do
    manifest_node=get_manifest_node('either_or_agree_disagree', :interaction_type => 'choiceInteraction', :bb_question_type => 'Either/Or')
    hash = Qti::ChoiceInteraction.create_instructure_question(:manifest_node=>manifest_node, :base_dir=>bb8_question_dir)
    hash[:answers].each {|a|a.delete(:id)}
    hash.should == BB8Expected::EITHER_OR_AGREE_DISAGREE
  end

  it "should convert either/or (true/false) into multiple choice" do
    manifest_node=get_manifest_node('either_or_true_false', :interaction_type => 'choiceInteraction', :bb_question_type => 'Either/Or')
    hash = Qti::ChoiceInteraction.create_instructure_question(:manifest_node=>manifest_node, :base_dir=>bb8_question_dir)
    hash[:answers].each {|a|a.delete(:id)}
    hash.should == BB8Expected::EITHER_OR_TRUE_FALSE
  end

  it "should convert either/or (right/wrong) into multiple choice" do
    manifest_node=get_manifest_node('either_or_right_wrong', :interaction_type => 'choiceInteraction', :bb_question_type => 'Either/Or')
    hash = Qti::ChoiceInteraction.create_instructure_question(:manifest_node=>manifest_node, :base_dir=>bb8_question_dir)
    hash[:answers].each {|a|a.delete(:id)}
    hash.should == BB8Expected::EITHER_OR_RIGHT_WRONG
  end

  it "should convert multiple answer questions" do
    manifest_node=get_manifest_node('multiple_answer', :interaction_type => 'choiceInteraction', :bb_question_type => 'Multiple Answer')
    hash = Qti::ChoiceInteraction.create_instructure_question(:manifest_node=>manifest_node, :base_dir=>bb8_question_dir)
    hash[:answers].each {|a|a.delete(:id)}
    hash.should == BB8Expected::MULTIPLE_ANSWER
  end

  it "should convert true/false questions" do
    manifest_node=get_manifest_node('true_false', :interaction_type => 'choiceInteraction', :bb_question_type => 'True/False')
    hash = Qti::ChoiceInteraction.create_instructure_question(:manifest_node=>manifest_node, :base_dir=>bb8_question_dir)
    hash[:answers].each {|a|a.delete(:id)}
    hash.should == BB8Expected::TRUE_FALSE
  end

  it "should convert essay questions" do
    manifest_node=get_manifest_node('essay', :interaction_type => 'extendedTextInteraction', :bb_question_type => 'Essay')
    hash = Qti::ChoiceInteraction.create_instructure_question(:manifest_node=>manifest_node, :base_dir=>bb8_question_dir)
    hash.should == BB8Expected::ESSAY
  end

  it "should convert short answer questions" do
    manifest_node=get_manifest_node('short_response', :interaction_type => 'extendedTextInteraction', :bb_question_type => 'Short Response')
    hash = Qti::ChoiceInteraction.create_instructure_question(:manifest_node=>manifest_node, :base_dir=>bb8_question_dir)
    hash.should == BB8Expected::SHORT_RESPONSE
  end

  it "should convert matching questions" do
    manifest_node=get_manifest_node('matching', :interaction_type => 'choiceInteraction', :bb_question_type => 'Matching')
    hash = Qti::ChoiceInteraction.create_instructure_question(:manifest_node=>manifest_node, :base_dir=>bb8_question_dir)
    # make sure the ids are correctly referencing each other
    matches = {}
    hash[:matches].each {|m| matches[m[:match_id]] = m[:text]}
    hash[:answers].each do |a|
      matches[a[:match_id]].should == a[:text].sub('left', 'right')
    end
    # compare everything else without the ids
    hash[:answers].each {|a|a.delete(:id); a.delete(:match_id)}
    hash[:matches].each {|m|m.delete(:match_id)}
    hash.should == BB8Expected::MATCHING
  end

  it "should convert opinion scale/likert questions into multiple choice questions" do
    manifest_node=get_manifest_node('likert', :interaction_type => 'choiceInteraction', :bb_question_type => 'Opinion Scale')
    hash = Qti::ChoiceInteraction.create_instructure_question(:manifest_node=>manifest_node, :base_dir=>bb8_question_dir)
    hash[:answers].each {|a|a.delete(:id)}
    hash.should == BB8Expected::LIKERT
  end

  it "should convert fill in the blank questions into short answer question"do
    manifest_node=get_manifest_node('fill_in_the_blank', :interaction_type => 'extendedTextInteraction', :bb_question_type => 'Fill in the Blank')
    hash = Qti::ChoiceInteraction.create_instructure_question(:manifest_node=>manifest_node, :base_dir=>bb8_question_dir)
    hash[:answers].each {|a|a.delete(:id)}
    hash.should == BB8Expected::FILL_IN_THE_BLANK
  end

  it "should flag file response questions as not supported" do
    manifest_node=get_manifest_node('file_upload', :interaction_type => 'extendedTextInteraction', :bb_question_type => 'File Upload')
    hash = Qti::ChoiceInteraction.create_instructure_question(:manifest_node=>manifest_node, :base_dir=>bb8_question_dir)
    hash.should == BB8Expected::FILE_RESPONSE
  end

  it "should flag hotspot questions as not supported" do
    manifest_node=get_manifest_node('hot_spot', :interaction_type => nil, :bb_question_type => 'Hot Spot')
    hash = Qti::ChoiceInteraction.create_instructure_question(:manifest_node=>manifest_node, :base_dir=>bb8_question_dir)
    hash.should == BB8Expected::HOT_SPOT
  end

  it "should flag quiz bowl questions as not supported" do
    manifest_node=get_manifest_node('quiz_bowl', :interaction_type => 'extendedTextInteraction', :bb_question_type => 'Quiz Bowl')
    hash = Qti::ChoiceInteraction.create_instructure_question(:manifest_node=>manifest_node, :base_dir=>bb8_question_dir)
    hash.should == BB8Expected::QUIZ_BOWL
  end

  it "should convert fill in multiple blanks questions" do
    manifest_node=get_manifest_node('fill_in_the_blank_plus', :interaction_type => 'extendedTextInteraction', :bb_question_type => 'Fill in the Blank Plus')
    hash = Qti::ChoiceInteraction.create_instructure_question(:manifest_node=>manifest_node, :base_dir=>bb8_question_dir)
    hash[:answers].each {|a|a.delete(:id)}
    hash.should == BB8Expected::FILL_IN_MULTIPLE_BLANKS
  end

  it "should convert jumbled sentence questions" do
    manifest_node=get_manifest_node('jumbled_sentence', :interaction_type => 'choiceInteraction', :bb_question_type => 'Jumbled Sentence')
    hash = Qti::ChoiceInteraction.create_instructure_question(:manifest_node=>manifest_node, :base_dir=>bb8_question_dir)
    hash[:answers].each {|a|a.delete(:id)}
    hash.should == BB8Expected::JUMBLED_SENTENCE
  end

  it "should convert ordering questions into matching questions" do
    manifest_node=get_manifest_node('ordering', :interaction_type => 'orderInteraction', :bb_question_type => 'Ordering')
    hash = Qti::ChoiceInteraction.create_instructure_question(:manifest_node=>manifest_node, :base_dir=>bb8_question_dir)
    # compare everything without the ids
    hash[:answers].each {|a|a.delete(:id); a.delete(:match_id)}
    hash[:matches].each {|m|m.delete(:match_id)}
    hash.should == BB8Expected::ORDER
  end

  it "should convert simple calculated questions" do
    manifest_node=get_manifest_node('calculated_simple', :interaction_type => 'extendedTextInteraction', :bb_question_type => 'Calculated')
    hash = Qti::ChoiceInteraction.create_instructure_question(:manifest_node=>manifest_node, :base_dir=>bb8_question_dir)
    hash[:answers].each {|a|a.delete(:id)}
    hash.should == BB8Expected::CALCULATED_SIMPLE
  end

  it "should convert complex calculated questions" do
    manifest_node=get_manifest_node('calculated_complex', :interaction_type => 'extendedTextInteraction', :bb_question_type => 'Calculated')
    hash = Qti::ChoiceInteraction.create_instructure_question(:manifest_node=>manifest_node, :base_dir=>bb8_question_dir)
    hash[:answers].each {|a|a.delete(:id)}
    hash.should == BB8Expected::CALCULATED_COMPLEX
  end

  it "should convert calculated numeric questions" do
    manifest_node=get_manifest_node('calculated_numeric', :interaction_type => 'extendedTextInteraction', :bb_question_type => 'Numeric')
    hash = Qti::ChoiceInteraction.create_instructure_question(:manifest_node=>manifest_node, :base_dir=>bb8_question_dir)
    hash[:answers].each {|a|a.delete(:id)}
    hash.should == BB8Expected::CALCULATED_NUMERIC
  end

  it "should convert the assessments into quizzes" do
    manifest_node=get_manifest_node('assessment', :quiz_type => 'Test')
    a = Qti::AssessmentTestConverter.new(manifest_node, bb8_question_dir, false)
    a.create_instructure_quiz
    a.quiz.should == BB8Expected::ASSESSMENT
  end


end

module BB8Expected
  # the multiple choice example minus the ids for the answers because those are random.
  MULTIPLE_CHOICE = {:answers=>
          [{:comments=>"right",
            :text=>"nose",
            :weight=>100,
            :migration_id=>"RESPONSE_595202876ccd425a9b4fe9e8e257292d"},
           {:text=>"ear",
            :weight=>0,
            :migration_id=>"RESPONSE_29b3b04b609c4a7abbf882e9b89b26ea"},
           {:text=>"eye",
            :weight=>0,
            :migration_id=>"aa35aa6b600844e1b42fd493cb0f0da7"},
           {:text=>"mouth",
            :weight=>0,
            :migration_id=>"b83b61f6356a410892de7f9c4a99b669"}],
                     :correct_comments=>"right",
                     :incorrect_comments=>"wrong",
                     :points_possible=>10.0,
                     :question_type=>"multiple_choice_question",
                     :question_name=>"",
                     :question_text=>"The answer is nose.<br />",
                     :migration_id=>"_153010_1"}

  MULTIPLE_CHOICE_BLANK_ANSWERS = {:question_name=>"",
                                   :question_text=>"This is a great question.<br\n />",
                                   :incorrect_comments=>"",
                                   :question_type=>"multiple_choice_question",
                                   :answers=>
                                           [{:text=>"True",
                                             :weight=>0,
                                             :migration_id=>"RESPONSE_44dc8fdb5e0a4c0c99de864f8a4ca983"},
                                            {:text=>"False",
                                             :comments=>"",
                                             :weight=>100,
                                             :migration_id=>"RESPONSE_73478560c56547f08cdc3eec5e363775"},
                                            {:text=>"No answer text provided.",
                                             :weight=>0,
                                             :migration_id=>"RESPONSE_78e36a7831e84a0f94ce01a151771f94"},
                                            {:text=>"No answer text provided.",
                                             :weight=>0,
                                             :migration_id=>"RESPONSE_686165cd422f45669b6be25b4f90f5de"}],
                                   :migration_id=>"_153271_1",
                                   :correct_comments=>"",
                                   :points_possible=>17.0}


  # removed ids on the answers
  TRUE_FALSE = {:answers=>
          [{:comments=>"yep", :text=>"true", :weight=>100, :migration_id=>"true"},
           {:text=>"false", :weight=>0, :migration_id=>"false"}],
                :correct_comments=>"yep",
                :incorrect_comments=>"nope",
                :points_possible=>10.0,
                :question_type=>"true_false_question",
                :question_name=>"",
                :question_text=>"I am wearing a black hat.<br />",
                :migration_id=>"_153015_1"}

  # removed ids on the answers
  MULTIPLE_ANSWER = {:answers=>
          [{:comments=>"right",
            :text=>"house",
            :weight=>100,
            :migration_id=>"RESPONSE_21c52601c6b545b39aab43c56749c2eb"},
           {:comments=>"right",
            :text=>"garage",
            :weight=>100,
            :migration_id=>"RESPONSE_2095979784cd45c9bcec8d303225ae16"},
           {:text=>"barn",
            :weight=>0,
            :migration_id=>"RESPONSE_08f1bd768b044f47881067ab7fcabac6"},
           {:text=>"pond",
            :weight=>0,
            :migration_id=>"dc9f2f878ce64fddbe762721e26fa11c"}],
                     :correct_comments=>"right",
                     :incorrect_comments=>"wrong",
                     :points_possible=>10.0,
                     :question_type=>"multiple_answers_question",
                     :question_name=>"",
                     :question_text=>"The answers are house and garage.<br />",
                     :migration_id=>"_153009_1"}

  ESSAY = {:example_solution=>"Nobody.",
           :migration_id=>"_153002_1",
           :answers=>[],
           :correct_comments=>"",
           :points_possible=>23.0,
           :question_name=>"",
           :question_text=>"Who likes to use Blackboard?<br />",
           :incorrect_comments=>"",
           :question_type=>"essay_question"}

  SHORT_RESPONSE =  {:migration_id=>"_153014_1",
                     :answers=>[],
                     :example_solution=>"A yellow submarine.",
                     :correct_comments=>"",
                     :incorrect_comments=>"",
                     :points_possible=>10.0,
                     :question_type=>"essay_question",
                     :question_name=>"",
                     :question_text=>"We all live in what?<br />"}

  # removed ids on the answers
  MATCHING = {:answers=>
          [{:text=>"left 1", :comments=>""},
           {:text=>"left 2", :comments=>""},
           {:text=>"left 3", :comments=>""},
           {:text=>"left 4", :comments=>""}],
              :correct_comments=>"right",
              :incorrect_comments=>"wrong",
              :points_possible=>10.0,
              :question_type=>"matching_question",
              :question_name=>"",
              :question_text=>"Match these.<br />",
              :migration_id=>"_153008_1",
              :matches=>
                      [{:text=>"right 1"},
                       {:text=>"right 2"},
                       {:text=>"right 3"},
                       {:text=>"right 4"}]}

  LIKERT = {:answers=>
          [{:text=>"Strongly Agree",
            :comments=>"right?",
            :weight=>100,
            :migration_id=>"RESPONSE_92f3633c39ff48a196b6f4c8fa5aa5cd"},
           {:text=>"Agree",
            :weight=>0,
            :migration_id=>"RESPONSE_71488ef738be49f18a724416eeab4386"},
           {:text=>"Neither Agree nor Disagree",
            :weight=>0,
            :migration_id=>"RESPONSE_61de00cfc52f43b79df933f886a4ccf9"},
           {:text=>"Disagree",
            :weight=>0,
            :migration_id=>"RESPONSE_82f60ef8ea194085bcb27efc7e50d24e"},
           {:text=>"Strongly Disagree",
            :weight=>0,
            :migration_id=>"d1d1010136854e07a8d24cff094c2201"},
           {:text=>"Not Applicable",
            :weight=>0,
            :migration_id=>"RESPONSE_159976c1152c4a10ace02ae35e27840e"}],
            :incorrect_comments=>"wrong?",
            :points_possible=>10.0,
            :question_type=>"multiple_choice_question",
            :question_name=>"",
            :migration_id=>"_153011_1",
            :question_text=>"You love Blackboard<br />",
            :correct_comments=>"right? "}

  FILL_IN_THE_BLANK = {:question_text=>"The answer is 'purple'.<br />",
                       :answers=>
                               [{:text=>"purple", :comments=>"", :weight=>100},
                                {:text=>"violet", :comments=>"", :weight=>100}],
                       :correct_comments=>"right",
                       :incorrect_comments=>"wrong",
                       :points_possible=>10.0,
                       :question_type=>"short_answer_question",
                       :question_name=>"",
                       :migration_id=>"_153005_1"}

  EITHER_OR_YES_NO = {:question_name=>"",
                      :answers=>
                              [{:text=>"yes", :migration_id=>"yes_no_true", :weight=>0},
                               {:text=>"no",
                                :migration_id=>"yes_no_false",
                                :comments=>"right answer",
                                :weight=>100}],
                      :migration_id=>"_153126_1",
                      :question_text=>"Either or question with yes/no",
                      :correct_comments=>"right answer",
                      :incorrect_comments=>"Wrong answer",
                      :points_possible=>10.0,
                      :question_type=>"multiple_choice_question"}

  EITHER_OR_AGREE_DISAGREE = {:question_type=>"multiple_choice_question",
                              :answers=>
                                      [{:text=>"agree", :weight=>0, :migration_id=>"agree_disagree_true"},
                                       {:text=>"disagree",
                                        :weight=>100,
                                        :migration_id=>"agree_disagree_false",
                                        :comments=>"correct answer"}],
                              :question_name=>"",
                              :migration_id=>"_153127_1",
                              :question_text=>"Either or question with agree/disagree.",
                              :correct_comments=>"correct answer",
                              :incorrect_comments=>"wrong answer",
                              :points_possible=>10.0}

  EITHER_OR_TRUE_FALSE = {:question_type=>"multiple_choice_question",
                          :answers=>
                                  [{:text=>"true", :weight=>0, :migration_id=>"true_false_true"},
                                   {:text=>"false",
                                    :weight=>100,
                                    :migration_id=>"true_false_false",
                                    :comments=>"r"}],
                          :question_name=>"",
                          :migration_id=>"_153128_1",
                          :question_text=>"Either/or question with true/false options",
                          :correct_comments=>"r",
                          :incorrect_comments=>"w",
                          :points_possible=>10.0}

  EITHER_OR_RIGHT_WRONG = {:question_type=>"multiple_choice_question",
                           :answers=>
                                   [{:text=>"right",
                                     :weight=>100,
                                     :migration_id=>"right_wrong_true",
                                     :comments=>"right"},
                                    {:text=>"wrong", :weight=>0, :migration_id=>"right_wrong_false"}],
                           :question_name=>"",
                           :migration_id=>"_153001_1",
                           :question_text=>"A duck is either a bird or a plane.<br />",
                           :correct_comments=>"right",
                           :incorrect_comments=>"wrong",
                           :points_possible=>7.0}

  FILE_RESPONSE = {:correct_comments=>"",
                   :answers=>[],
                   :incorrect_comments=>"",
                   :points_possible=>10.0,
                   :unsupported=>true,
                   :question_type=>"File Upload",
                   :question_name=>"",
                   :migration_id=>"_153003_1",
                   :question_text=>"File response question. I don't know what this is.<br />"}

  HOT_SPOT = {:answers=>[],
              :question_name=>"",
              :migration_id=>"_153006_1",
              :question_text=>"Where are the nuts?<br />",
              :correct_comments=>"",
              :incorrect_comments=>"",
              :unsupported=>true,
              :points_possible=>10.0,
              :question_type=>"Hot Spot"}

  QUIZ_BOWL = {:answers=>[],
               :question_type=>"Quiz Bowl",
               :question_name=>"",
               :migration_id=>"_153013_1",
               :question_text=>"Yellow",
               :correct_comments=>"",
               :incorrect_comments=>"",
               :unsupported=>true,
               :points_possible=>10.0}

  FILL_IN_MULTIPLE_BLANKS = {:answers=>
          [{:text=>"poor", :comments=>"", :blank_id=>"poor", :weight=>100},
           {:text=>"sad", :comments=>"", :blank_id=>"poor", :weight=>100},
           {:text=>"family", :comments=>"", :blank_id=>"family", :weight=>100}],
                             :incorrect_comments=>"wrong",
                             :points_possible=>10.0,
                             :question_type=>"fill_in_multiple_blanks_question",
                             :question_name=>"",
                             :migration_id=>"_153004_1",
                             :question_text=>"I'm just a [poor] boy from a poor [family]<br />",
                             :correct_comments=>"right"}

  JUMBLED_SENTENCE = {
          :answers=>
                  [
                          {:text=>"brown", :blank_id=>"brown", :weight=>100, :migration_id=>"RESPONSE_8197c164fada4325968bb1a0a031bb01"},
                          {:text=>"jumped", :blank_id=>"brown", :weight=>0, :migration_id=>"RESPONSE_6aeed8b3413b432cb706243be1e44d99"},
                          {:text=>"fence", :blank_id=>"brown", :weight=>0, :migration_id=>"fb1be73070444e31b8c7d349bc1f0144"},
                          {:text=>"ditch", :blank_id=>"brown", :weight=>0, :migration_id=>"a7fd8ffef02647ca82c9f4097fd1b088"},
                          {:text=>"brown", :blank_id=>"jumped", :weight=>0, :migration_id=>"RESPONSE_8197c164fada4325968bb1a0a031bb01"},
                          {:text=>"jumped", :blank_id=>"jumped", :weight=>100, :migration_id=>"RESPONSE_6aeed8b3413b432cb706243be1e44d99"},
                          {:text=>"fence", :blank_id=>"jumped", :weight=>0, :migration_id=>"fb1be73070444e31b8c7d349bc1f0144"},
                          {:text=>"ditch", :blank_id=>"jumped", :weight=>0, :migration_id=>"a7fd8ffef02647ca82c9f4097fd1b088"},
                          {:text=>"brown", :blank_id=>"fence", :weight=>0, :migration_id=>"RESPONSE_8197c164fada4325968bb1a0a031bb01"},
                          {:text=>"jumped", :blank_id=>"fence", :weight=>0, :migration_id=>"RESPONSE_6aeed8b3413b432cb706243be1e44d99"},
                          {:text=>"fence", :blank_id=>"fence", :weight=>100, :migration_id=>"fb1be73070444e31b8c7d349bc1f0144"},
                          {:text=>"ditch", :blank_id=>"fence", :weight=>0, :migration_id=>"a7fd8ffef02647ca82c9f4097fd1b088"},
                  ],
          :incorrect_comments=>"wrong",
          :points_possible=>10.0,
          :question_type=>"multiple_dropdowns_question",
          :question_name=>"",
          :migration_id=>"_153007_1",
          :question_text=>"The quick [brown] fox [jumped] over the [fence].<br />",
          :correct_comments=>"right"
  }

  ORDER = {:answers=>
          [{:text=>"1", :comments=>""},
           {:text=>"2", :comments=>""},
           {:text=>"3", :comments=>""},
           {:text=>"4", :comments=>""}],
           :correct_comments=>"right",
           :incorrect_comments=>"wrong",
           :points_possible=>10.0,
           :question_type=>"matching_question",
           :question_name=>"",
           :question_text=>"It is in numerical order.<br />",
           :migration_id=>"_153012_1",
           :matches=>
                   [{:text=>"b"},
                    {:text=>"a"},
                    {:text=>"c"},
                    {:text=>"d"}]}

  CALCULATED_SIMPLE = {:partial_credit_tolerance=>"0.1",
                       :points_possible=>10.0,
                       :answers=>
                               [{:migration_id=>"6fbdfcb8a24143769d537f69e7e9a9b7",
                                 :answer=>"9",
                                 :variables=>[{:value=>"1.0", :name=>"x"}]},
                                {:migration_id=>"78de3040f31549919cff0e67bd80e42f",
                                 :answer=>"8",
                                 :variables=>[{:value=>"2.0", :name=>"x"}]},
                                {:migration_id=>"aec7518b9a3a4b45836ffc80b747abdf",
                                 :answer=>"16",
                                 :variables=>[{:value=>"-6.0", :name=>"x"}]},
                                {:migration_id=>"5d6b8a47168b4f89a9b2c5a7eefbd5b7",
                                 :answer=>"6",
                                 :variables=>[{:value=>"4.0", :name=>"x"}]},
                                {:migration_id=>"629a233516f949278cc931520c591fb6",
                                 :answer=>"16",
                                 :variables=>[{:value=>"-6.0", :name=>"x"}]},
                                {:migration_id=>"35b297145adb4cf1bc799c8e498d1995",
                                 :answer=>"10",
                                 :variables=>[{:value=>"0.0", :name=>"x"}]},
                                {:migration_id=>"73f88ad3f68e445ca9a5486ea04c4425",
                                 :answer=>"15",
                                 :variables=>[{:value=>"-5.0", :name=>"x"}]},
                                {:migration_id=>"cab5c8761c26479592f14e149ac9166d",
                                 :answer=>"3",
                                 :variables=>[{:value=>"7.0", :name=>"x"}]},
                                {:migration_id=>"76a4b922a2054a5a9c2a972dbee00f31",
                                 :answer=>"10",
                                 :variables=>[{:value=>"0.0", :name=>"x"}]},
                                {:migration_id=>"b6e855950daf4fa3bb014907503b3a60",
                                 :answer=>"18",
                                 :variables=>[{:value=>"-8.0", :name=>"x"}]}],
                       :unit_points_percent=>"15.0",
                       :question_type=>"calculated_question",
                       :unit_value=>"cm",
                       :question_name=>"",
                       :unit_required=>true,
                       :migration_id=>"_152999_1",
                       :question_text=>"What is 10 - [x]?<br\n />",
                       :unit_case_sensitive=>false,
                       :correct_comments=>"You got it right!",
                       :variables=>[{:min=>"-10.0", :scale=>"0", :max=>"10.0", :name=>"x"}],
                       :partial_credit_points_percent=>"25.0",
                       :incorrect_comments=>"You got it wrong...",
                       :answer_tolerance=>"0.0",
                       :imported_formula=>
                               "<math><apply><minus/><cn>10</cn><ci>x</ci></apply></math>"}

  CALCULATED_COMPLEX = {:unit_points_percent=>"0.0",
                        :incorrect_comments=>"Wrong.",
                        :question_bank_name=>"Pool 1",
                        :answers=>
                                [{:answer=>"96.291",
                                  :migration_id=>"e50431e628554922b5a361aa7665adfa",
                                  :variables=>
                                          [{:value=>"37.0", :name=>"F"},
                                           {:value=>"26.0", :name=>"Y"},
                                           {:value=>"5.43", :name=>"i"},
                                           {:value=>"59.0", :name=>"n"},
                                           {:value=>"5.0", :name=>"r"}]},
                                 {:answer=>"112.703",
                                  :migration_id=>"9f2c947f88aa4666a0fd63b45edc3a59",
                                  :variables=>
                                          [{:value=>"46.0", :name=>"F"},
                                           {:value=>"36.0", :name=>"Y"},
                                           {:value=>"5.22", :name=>"i"},
                                           {:value=>"104.0", :name=>"n"},
                                           {:value=>"6.0", :name=>"r"}]},
                                 {:answer=>"101.325",
                                  :migration_id=>"b2fdbbd25ce945b0842a2c0da1378429",
                                  :variables=>
                                          [{:value=>"31.0", :name=>"F"},
                                           {:value=>"35.0", :name=>"Y"},
                                           {:value=>"5.94", :name=>"i"},
                                           {:value=>"33.0", :name=>"n"},
                                           {:value=>"6.0", :name=>"r"}]},
                                 {:answer=>"114.764",
                                  :migration_id=>"7dd028c5676444ee90b9993f6cf7b33f",
                                  :variables=>
                                          [{:value=>"29.0", :name=>"F"},
                                           {:value=>"34.0", :name=>"Y"},
                                           {:value=>"4.1", :name=>"i"},
                                           {:value=>"85.0", :name=>"n"},
                                           {:value=>"5.0", :name=>"r"}]},
                                 {:answer=>"105.938",
                                  :migration_id=>"8cb4f1ae3e9d400f8e921c3f569220b1",
                                  :variables=>
                                          [{:value=>"34.0", :name=>"F"},
                                           {:value=>"25.0", :name=>"Y"},
                                           {:value=>"4.48", :name=>"i"},
                                           {:value=>"23.0", :name=>"n"},
                                           {:value=>"5.0", :name=>"r"}]},
                                 {:answer=>"102.415",
                                  :migration_id=>"356041a98ad34c2695637d4d628203c9",
                                  :variables=>
                                          [{:value=>"20.0", :name=>"F"},
                                           {:value=>"25.0", :name=>"Y"},
                                           {:value=>"4.87", :name=>"i"},
                                           {:value=>"76.0", :name=>"n"},
                                           {:value=>"5.0", :name=>"r"}]},
                                 {:answer=>"113.719",
                                  :migration_id=>"9c4f1f570806436694ee00c82c534350",
                                  :variables=>
                                          [{:value=>"29.0", :name=>"F"},
                                           {:value=>"31.0", :name=>"Y"},
                                           {:value=>"5.04", :name=>"i"},
                                           {:value=>"87.0", :name=>"n"},
                                           {:value=>"6.0", :name=>"r"}]},
                                 {:answer=>"102.09",
                                  :migration_id=>"a031adda386d46d0b253b050063a94f9",
                                  :variables=>
                                          [{:value=>"39.0", :name=>"F"},
                                           {:value=>"20.0", :name=>"Y"},
                                           {:value=>"4.88", :name=>"i"},
                                           {:value=>"84.0", :name=>"n"},
                                           {:value=>"5.0", :name=>"r"}]},
                                 {:answer=>"106.802",
                                  :migration_id=>"050321d9bd8348af8ddfed3a889638c0",
                                  :variables=>
                                          [{:value=>"32.0", :name=>"F"},
                                           {:value=>"26.0", :name=>"Y"},
                                           {:value=>"4.52", :name=>"i"},
                                           {:value=>"104.0", :name=>"n"},
                                           {:value=>"5.0", :name=>"r"}]},
                                 {:answer=>"101.954",
                                  :migration_id=>"cf6496b867424188ad0ee3f28b1e1a5d",
                                  :variables=>
                                          [{:value=>"44.0", :name=>"F"},
                                           {:value=>"39.0", :name=>"Y"},
                                           {:value=>"4.9", :name=>"i"},
                                           {:value=>"30.0", :name=>"n"},
                                           {:value=>"5.0", :name=>"r"}]}],
                        :answer_tolerance=>"0.1",
                        :points_possible=>10.0,
                        :imported_formula=>
                                "<math><apply><times/><apply><power/><apply><times/><cn>10</cn><ci>F</ci></apply><apply><minus/><cn>1</cn></apply></apply><apply><plus/><apply><times/><cn>1000</cn><ci>F</ci><ci>r</ci><apply><power/><ci>i</ci><apply><minus/><cn>1</cn></apply></apply><apply><minus/><cn>1</cn><apply><power/><apply><plus/><cn>1</cn><apply><divide/><ci>i</ci><cn>200</cn></apply></apply><apply><minus/><apply><times/><cn>2</cn><apply><minus/><ci>Y</ci><cn>10</cn></apply></apply></apply></apply></apply></apply><apply><times/><cn>1000</cn><ci>F</ci><apply><power/><apply><plus/><cn>1</cn><apply><divide/><ci>i</ci><cn>200</cn></apply></apply><apply><minus/><apply><times/><cn>2</cn><apply><minus/><ci>Y</ci><cn>10</cn></apply></apply></apply></apply></apply></apply><apply><plus/><cn>1</cn><apply><times/><apply><divide/><ci>i</ci><cn>100</cn></apply><apply><divide/><ci>n</ci><cn>360</cn></apply></apply></apply></apply></math>",
                        :unit_required=>false,
                        :question_type=>"calculated_question",
                        :partial_credit_tolerance=>"0",
                        :unit_case_sensitive=>false,
                        :question_name=>"",
                        :migration_id=>"_153086_1",
                        :question_text=>
                                "Based on her excellent\n performance as a district sales manager, Maria receives a\n sizable bonus at work. Since her generous salary is more\n than enough to provide for the needs of her family, she\n decides to use the bonus to buy a bond as an investment.\n The par value of the bond that Maria would like to\n purchase is $[F] thousand. The bond pays [r]% interest,\n compounded semiannually (with payment on January 1 and\n July 1) and matures on July 1, 20[Y]. Maria wants a return\n of [i]%, compounded semiannually. How much would she be\n willing to pay for the bond if she buys it [n] days after\n the July 2010 interest anniversary? Give your answer in\n the format of a quoted bond price, as a percentage of par\n to three decimal places -- like you would see in the Wall\n Street Journal. Use the formula discussed in class -- and\n from the book, NOT the HP 12c bond feature. (Write only\n the digits, to three decimal palces, e.g. 114.451 and no\n $, commas, formulas, etc.)",
                        :variables=>
                                [{:min=>"20.0", :max=>"50.0", :scale=>"0", :name=>"F"},
                                 {:min=>"20.0", :max=>"40.0", :scale=>"0", :name=>"Y"},
                                 {:min=>"4.0", :max=>"6.0", :scale=>"2", :name=>"i"},
                                 {:min=>"20.0", :max=>"120.0", :scale=>"0", :name=>"n"},
                                 {:min=>"5.0", :max=>"7.0", :scale=>"0", :name=>"r"}],
                        :correct_comments=>"Right answer.",
                        :partial_credit_points_percent=>"0.0"}

  CALCULATED_NUMERIC = {:migration_id=>"_153000_1",
                        :answers=>
                                [{:end=>4.0,
                                  :numerical_answer_type=>"range_answer",
                                  :start=>4.0,
                                  :exact=>4.0,
                                  :comments=>"",
                                  :weight=>100}],
                        :question_text=>"What is 10 - 6?<br />",
                        :question_bank_name=>"Pool 1",
                        :correct_comments=>"Right.",
                        :incorrect_comments=>"Left",
                        :points_possible=>10.0,
                        :question_type=>"numerical_question",
                        :question_name=>""}

  ASSESSMENT = {:points_possible=>"237.0",
                :questions=>
                        [{:question_type=>"question_reference", :migration_id=>"_153086_1"},
                         {:question_type=>"question_reference", :migration_id=>"_152999_1"},
                         {:question_type=>"question_reference", :migration_id=>"_153000_1"},
                         {:question_type=>"question_reference", :migration_id=>"_153002_1"},
                         {:question_type=>"question_reference", :migration_id=>"_153003_1"},
                         {:question_type=>"question_reference", :migration_id=>"_153004_1"},
                         {:question_type=>"question_reference", :migration_id=>"_153005_1"},
                         {:question_type=>"question_reference", :migration_id=>"_153006_1"},
                         {:question_type=>"question_reference", :migration_id=>"_153007_1"},
                         {:question_type=>"question_reference", :migration_id=>"_153008_1"},
                         {:question_type=>"question_reference", :migration_id=>"_153009_1"},
                         {:question_type=>"question_reference", :migration_id=>"_153010_1"},
                         {:question_type=>"question_reference", :migration_id=>"_153011_1"},
                         {:question_type=>"question_reference", :migration_id=>"_153012_1"},
                         {:question_type=>"question_reference", :migration_id=>"_153013_1"},
                         {:question_type=>"question_reference", :migration_id=>"_153014_1"},
                         {:question_type=>"question_reference", :migration_id=>"_153015_1"},
                         {:question_type=>"question_reference", :migration_id=>"_153126_1"},
                         {:question_type=>"question_reference", :migration_id=>"_153127_1"},
                         {:question_type=>"question_reference", :migration_id=>"_153128_1"},
                         {:question_type=>"question_reference", :migration_id=>"_153001_1"},
                         {:question_type=>"question_reference", :migration_id=>"_153271_1"}],
                :question_count=>22,
                :title=>"Blackboard 8 Export Test",
                :quiz_name=>"Blackboard 8 Export Test",
                :quiz_type=>"assignment",
                :migration_id=>"res00001",
                :grading=>
                        {
                                :migration_id=>"res00001",
                                :title=>"Blackboard 8 Export Test",
                                :points_possible=>"237.0",
                                :grade_type=>"numeric",
                                :due_date=>nil,
                                :weight=>nil
                        }
  }
end