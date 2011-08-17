var find_outcome = (function() {
  return {
    find: function(callback, options) {
      options = options || {};
      find_outcome.callback = callback;
      var $dialog = $("#find_outcome_criterion_dialog");
      if(!$dialog.hasClass('loaded')) {
        $dialog.find(".loading_message").text("Loading Outcomes...");
        $.ajaxJSON($dialog.find(".outcomes_list_url").attr('href'), 'GET', {}, function(data) {
          valids = [];
          for(var idx in data) {
            var outcome = data[idx].learning_outcome;
            if(!options.for_rubric || (outcome.data && outcome.data.rubric_criterion)) {
              valids.push(outcome);
            }
          }
          if(valids.length === 0) {
            $dialog.find(".loading_message").text("No" + (options.for_rubric ? " Rubric-Configured" : "") + " Outcomes found");
          } else {
            $dialog.find(".loading_message").hide();
            $dialog.addClass('loaded');
            for(var idx in valids) {
              var outcome = valids[idx];
              outcome.name = outcome.short_description;
              outcome.mastery_points = outcome.data.rubric_criterion.mastery_points || outcome.data.rubric_criterion.points_possible;
              var $name = $dialog.find(".outcomes_select.blank:first").clone(true).removeClass('blank');
              outcome.title = outcome.short_description;
              var $text = $("<div/>");
              $text.text(outcome.short_description);
              outcome.title = $.truncateText($.trim($text.text()), 35);
              outcome.display_name = outcome.cached_context_short_name || "";
              $name.fillTemplateData({data: outcome});
              $dialog.find(".outcomes_selects").append($name.show());
              var $outcome = $dialog.find(".outcome.blank:first").clone(true).removeClass('blank');
              $outcome
                .find(".mastery_level").attr('id', 'outcome_question_bank_mastery_' + outcome.id).end()
                .find(".mastery_level_text").attr('for', 'outcome_question_bank_mastery_' + outcome.id);
              outcome.learning_outcome_id = outcome.id;
              var criterion = outcome.data && outcome.data.rubric_criterion
              var pct = (criterion.points_possible && criterion.mastery_points != null && (criterion.mastery_points / criterion.points_possible)) || 0;
              pct = (Math.round(pct * 10000) / 100.0) || "";
              $outcome.find(".mastery_level").val(pct);
              $outcome.fillTemplateData({data: outcome, htmlValues: ['description']});
              $outcome.addClass('outcome_' + outcome.id);
              if(outcome.data && outcome.data.rubric_criterion) {
                for(var jdx in outcome.data.rubric_criterion.ratings) {
                  var rating = outcome.data.rubric_criterion.ratings[jdx];
                  var $rating = $outcome.find(".rating.blank").clone(true).removeClass('blank');
                  $rating.fillTemplateData({data: rating});
                  $outcome.find("tr").append($rating.show());
                }
              }
              $dialog.find(".outcomes_list").append($outcome);
            }
            $dialog.find(".outcomes_select:not(.blank):first").click();
          }
        }, function(data) {
          $dialog.find(".loading_message").text("Outcomes Retrieval failed unexpected.  Please try again.");
        });
      }
      $dialog.dialog('close').dialog({
        autoOpen: false,
        modal: true,
        title: "Find Outcome" + (options.for_rubric ? " Criterion" : ""),
        width: 700,
        height: 400
      }).dialog('open');
    }
  }
})();
window.find_outcome = find_outcome;
$(document).ready(function() {
  $("#find_outcome_criterion_dialog .outcomes_select").click(function(event) {
    event.preventDefault();
    $("#find_outcome_criterion_dialog .outcomes_select.selected_side_tab").removeClass('selected_side_tab');
    $(this).addClass('selected_side_tab');
    var id = $(this).getTemplateData({textValues: ['id']}).id;
    $("#find_outcome_criterion_dialog .outcomes_list .outcome").hide();
    $("#find_outcome_criterion_dialog .outcomes_list .outcome_" + id).show();
  });
  $("#find_outcome_criterion_dialog .select_outcome_link").click(function(event) {
    event.preventDefault();
    var $outcome = $(this).parents(".outcome");
    $("#find_outcome_criterion_dialog").dialog('close');
    if($.isFunction(find_outcome.callback)) {
      find_outcome.callback($outcome);
    }
  });
});