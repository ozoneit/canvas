module Qti
class AssociateInteraction < AssessmentItemConverter

  def initialize(opts)
    super(opts)
    @question[:matches] = []
    @question[:question_type] = 'matching_question'
    # to mark whether it's bb8/vista/respondus_matching if needed
    @flavor = opts[:custom_type]
  end

  def parse_question_data
    if @doc.at_css('associateinteraction')
      match_map = {}
      get_all_matches_with_interaction(match_map)
      get_all_answers_with_interaction(match_map)
      check_for_meta_matches
    elsif node = @doc.at_css('matchinteraction')
      get_all_match_interaction(node)
    elsif @flavor == 'respondus_matching'
      get_respondus_answers
      get_respondus_matches
    else
      get_all_matches_from_body
      get_all_answers_from_body
    end
    get_feedback()
    @question
  end
  
  private

  def get_respondus_answers
    @doc.css('choiceinteraction').each do |a|
      answer = {}
      @question[:answers] << answer
      answer[:text] = a.at_css('prompt').text
      answer[:id] = unique_local_id
      answer[:migration_id] = a['responseidentifier']
      answer[:comments] = ""
      #answer[:match_id] = @question[:matches][i][:match_id]
    end
  end

  def get_respondus_matches
    @question[:answers].each do |answer|
      @doc.css('responseif, responseelseif').each do |r_if|
        if r_if.at_css("match variable[identifier=#{answer[:migration_id]}]") && r_if.at_css('setoutcomevalue[identifier$=_CORRECT]')
          match = {}
          @question[:matches] << match
          migration_id = r_if.at_css('match basevalue').text
          match[:text] = @doc.at_css("simplechoice[identifier=#{migration_id}] p").text
          match[:match_id] = unique_local_id
          answer[:match_id] = match[:match_id]
          answer.delete :migration_id
          break
        end
      end
    end
  end

  def get_all_matches_from_body
    if matches = @doc.at_css('div.RIGHT_MATCH_BLOCK')
      matches.css('p').each do |m|
        match = {}
        @question[:matches] << match
        match[:text] = clear_html m.text.strip
        match[:match_id] = unique_local_id
      end
    end
  end
  
  def get_all_answers_from_body
    @doc.css('div.RESPONSE_BLOCK p').each_with_index do |a, i|
      answer = {}
      @question[:answers] << answer
      answer[:text] = clear_html a.text.strip
      answer[:id] = unique_local_id 
      answer[:comments] = ""
      answer[:match_id] = @question[:matches][i][:match_id]
    end
  end
  
  def get_all_matches_with_interaction(match_map)
    if matches = @doc.at_css('associateinteraction')
      matches.css('simpleassociablechoice').each do |m|
        match = {}
        @question[:matches] << match
        match[:text] = m.text.strip
        match[:match_id] = unique_local_id
        match_map[match[:text]] = match[:match_id]
      end
    end
  end
  
  def get_all_answers_with_interaction(match_map)
    @doc.css('associateinteraction').each do |a|
      answer = {}
      @question[:answers] << answer
      answer[:text] = a.at_css('prompt').text.strip
      answer[:id] = unique_local_id 
      answer[:comments] = ""
      
      if option = a.at_css('simpleassociablechoice[identifier^=MATCH]')
        answer[:match_id] = match_map[option.text.strip]
      end
    end
  end
  
  # Replaces the matches with their full-text instead of a,b,c/1,2,3/etc.
  def check_for_meta_matches
    if long_matches = @doc.search('instructuremetadata matchingmatch')
      @question[:matches].each_with_index do |match, i|
        match[:text] = long_matches[i].text.strip.gsub(/ +/, " ") if long_matches[i]
      end
      if not long_matches.size == @question[:matches].size
        @question[:qti_warning] = "The matching options for this question may have been incorrectly imported."
      end
    end
  end

  def get_all_match_interaction(interaction_node)
    answer_map={}
    interaction_node.at_css('simplematchset').css('simpleassociablechoice').each do |node|
      answer = {}
      answer[:text] = node.text.strip
      answer[:id] = unique_local_id
      @question[:answers] << answer
      id = get_node_val(node, '@identifier')
      answer_map[id] = answer
    end

    match_map = {}
    interaction_node.css('simplematchset').last.css('simpleassociablechoice').each do |node|
      match = {}
      match[:text] = node.text.strip
      match[:match_id] = unique_local_id
      @question[:matches] << match
      id = get_node_val(node, '@identifier')
      match_map[id] = match
    end

    #Check if there are correct answers explicitly specified
    @doc.css('correctresponse > value').each do |match|
      answer_id, match_id = match.text.split
      if answer = answer_map[answer_id.strip] and m = match_map[match_id.strip]
        answer[:match_id] = m[:match_id]
      end
    end
  end

end
end
