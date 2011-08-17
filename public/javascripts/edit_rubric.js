/**
 * Copyright (C) 2011 Instructure, Inc.
 *
 * This file is part of Canvas.
 *
 * Canvas is free software: you can redistribute it and/or modify it under
 * the terms of the GNU Affero General Public License as published by the Free
 * Software Foundation, version 3 of the License.
 *
 * Canvas is distributed in the hope that it will be useful, but WITHOUT ANY
 * WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
 * A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
 * details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program. If not, see <http://www.gnu.org/licenses/>.
 */

var rubricEditing = {
  htmlBody: null,
  
  updateCriteria: function($rubric) {
    $rubric.find(".criterion:not(.blank)").each(function(i) {
      $(this).attr('id', 'criterion_' + (i + 1));
    });
  },
  addCriterion: function($rubric) {
    var $blank = $rubric.find(".criterion.blank:first");
    var $criterion = $blank.clone(true);
    $criterion.removeClass('blank');
    $rubric.find(".summary").before($criterion.show());
    rubricEditing.updateCriteria($rubric);
    rubricEditing.updateRubricPoints($rubric);
    rubricEditing.sizeRatings($criterion);
    return $criterion;
  },
  findOutcomeCriterion: function($rubric) {
    $("#find_outcome_criterion_dialog").data('current_rubric', $rubric);
    find_outcome.find(function($outcome) {
      if(!$("#find_outcome_criterion_dialog").data('current_rubric')) { return; }
      var $rubric = $("#find_outcome_criterion_dialog").data('current_rubric');
      var outcome_id = $outcome.find(".learning_outcome_id").text();
      $rubric.find(".criterion.learning_outcome_" + outcome_id).find(".delete_criterion_link").click();
      $rubric.find(".add_criterion_link").click();
      var $criterion = $rubric.find(".criterion:not(.blank):last");
      $criterion.toggleClass('ignore_criterion_for_scoring', !$outcome.find(".criterion_for_scoring").attr('checked'));
      $criterion.find(".mastery_points").val($outcome.find(".mastery_points").text());
      $criterion.addClass("learning_outcome_criterion");
      $criterion.find(".learning_outcome_id").text(outcome_id);
      $criterion.find(".criterion_points").val($outcome.find(".rating:not(.blank):first .points").text()).blur();
      for(var idx = 0; idx < $outcome.find(".rating:not(.blank)").length - 2; idx++) {
        $criterion.find(".rating:not(.blank):first").addClass('add_column').click();
      }
      $criterion.find(".rating:not(.blank)").each(function(i) {
        var data = $outcome.find(".rating:not(.blank)").eq(i).getTemplateData({textValues: ['description', 'points']});
        $(this).fillTemplateData({data: data});
      });
      var long_description = $outcome.find(".body.description").html();
      var mastery_points = $outcome.find(".mastery_points").text();
      $criterion.find(".cancel_button").click();
      $criterion.find(".long_description").val(long_description);
      $criterion.find(".long_description_holder").toggleClass('empty', !long_description);
      $criterion.find(".criterion_description_value").text($outcome.find(".short_description").text());
      $criterion.find(".criterion_description").val($outcome.find(".short_description").text()).focus().select();
      $criterion.find(".mastery_points").text(mastery_points);
    }, {for_rubric: true});
  },
  hideCriterionAdd: function($rubric) {
    $rubric.find('.add_right, .add_left, .add_column').removeClass('add_left add_right add_column');
  },
  updateRubricPoints: function($rubric) {
    var total = 0;
    $rubric.find(".criterion:not(.blank):not(.ignore_criterion_for_scoring) .criterion_points").each(function() {
      var points = parseFloat($(this).val(), 10);
      if(!isNaN(points)) {
        total += points;
      }
    });
    $rubric.find(".rubric_total").text(total);
  },
  updateCriterionPoints: function($criterion, baseOnRatings) {
    rubricEditing.hideEditRating();
    var ratings = $.makeArray($criterion.find(".rating")).reverse();
    var rating_points = -1;
    var points = parseFloat($criterion.find(".criterion_points").val());
    if(isNaN(points)) {
      points = 5;
    }
    $criterion.find(".rating:first .points").text(points);
    // From right to left, make sure points always increase by at least one
    $.each(ratings, function(i, rating) {
      var $rating = $(rating);
      var data = $rating.getTemplateData({textValues: ['points']});
      if(data.points < rating_points) {
        data.points = rating_points + 1;
        $rating.fillTemplateData({data: data});
      }
      rating_points = parseFloat(data.points);
    });
    if(baseOnRatings && rating_points > points) { points = rating_points; }
    $criterion.find(".criterion_points").val(points);
    $criterion.find(".display_criterion_points").text(points);
    if(!$criterion.data('criterion_points') || $criterion.data('criterion_points') != points) {
      if(!$criterion.data('criterion_points')) {
        var pts = parseFloat($criterion.find(".rating:first .points").text());
        $criterion.data('criterion_points', pts);
      }
      var oldMax = parseFloat($criterion.data('criterion_points'));
      var newMax = points;
      var $ratingList = $criterion.find(".rating");
      $($ratingList[0]).find(".points").text(points);
      var lastPts = points;
      // From left to right, scale points proportionally to new range.
      // So if originally they were 3,2,1 and now we increased the
      // total possible to 9, they'd be 9,6,3
      for(var i = 1; i < $ratingList.length - 1; i++) {
        var pts = parseFloat($($ratingList[i]).find(".points").text());
        var newPts = Math.round((pts / oldMax) * newMax);
        if(isNaN(pts) || (pts == 0 && lastPts > 0)) {
          newPts = lastPts - Math.round(lastPts / ($ratingList.length - i));
        }
        if(newPts >= lastPts) {
          newPts = lastPts - 1;
        }
        newPts = Math.max(0, newPts);
        lastPts = newPts;
        $($ratingList[i]).find(".points").text(newPts);
      }
      $criterion.data('criterion_points', points);
    }
    rubricEditing.updateRubricPoints($criterion.parents(".rubric"));
  },
  editRating: function($rating) {
    if(!$rating.parents(".rubric").hasClass('editing')) { return; }
    rubricEditing.hideEditRating(true);
    rubricEditing.hideCriterionAdd($rating.parents(".rubric"));
    var height = Math.max(40, $rating.find(".rating").height());
    var data = $rating.getTemplateData({textValues: ['description', 'points']});
    var $box = $("#edit_rating");
    $box.fillFormData(data);
    $rating.find(".container").hide();
    $rating.append($box.show());
    $box.find(":input:first").focus().select();
    $rating.addClass('editing');
    rubricEditing.sizeRatings($rating.parents(".criterion"));
  },
  hideEditRating: function(updateCurrent) {
    var $form = $("#edit_rating");
    if($form.filter(":visible").length > 0 && updateCurrent) { $form.find("form").submit(); }
    var $rating = $form.parents(".rating");
    $rating.removeClass('editing');
    $form.appendTo($("body")).hide();
    $rating.find(".container").show();
    rubricEditing.sizeRatings($rating.parents(".criterion"));
    rubricEditing.hideCriterionAdd($rating.parents(".rubric"));
  },
  editCriterion: function($criterion) {
    if(!$criterion.parents(".rubric").hasClass('editing')) { return; }
    rubricEditing.hideEditCriterion(true);
    var $td = $criterion.find(".criterion_description");
    var height = Math.max(40, $td.find(".description").height());
    var data = $td.getTemplateData({textValues: ['description']});
    var $box = $("#edit_criterion");
    $box.fillFormData(data);
    $td.find(".container").hide().after($box.show());
    $box.find(":input:first").focus().select();
    rubricEditing.sizeRatings($criterion);
  },
  hideEditCriterion: function(updateCurrent) {
    var $form = $("#edit_criterion");
    if($form.filter(":visible").length > 0 && updateCurrent) { $form.find("form").submit(); }
    var $criterion = $form.parents(".criterion");
    $form.appendTo("body").hide();
    $criterion.find(".criterion_description").find(".container").show();
    rubricEditing.sizeRatings($criterion);
  },
  
  originalSizeRatings: function() {
    var $visibleCriteria = $(".rubric:not(.rubric_summary) .criterion:visible");
    if ($visibleCriteria.length) {
      var scrollTop = $.windowScrollTop();
      $visibleCriteria.each(function() {
        var $this = $(this),
            $ratings = $this.find(".ratings:visible");
        if($ratings.length) {
          var $ratingsContainers = $ratings.find('.rating .container').css('height', ""),
              maxHeight = Math.max(
                $ratings.height(),
                $this.find(".criterion_description .container").height()
              );
          // the -10 here is the padding on the .container.
          $ratingsContainers.css('height', (maxHeight - 10) + 'px');        
        }
      });
      rubricEditing.htmlBody.scrollTop(scrollTop); 
    }
  },
  
  rubricData: function($rubric) {
    $rubric = $rubric.filter(":first");
    if(!$rubric.hasClass('editing')) {
      $rubric = $rubric.next(".editing");
    }
    $rubric.find(".criterion_points").each(function() {
      var val = $(this).val();
      $(this).parents(".criterion").find(".display_criterion_points").text(val);
    });
    var vals = $rubric.getFormData();
    $rubric.find("thead .title").text(vals.title);
    var vals = $rubric.getTemplateData({textValues: ['title', 'description', 'rubric_total', 'rubric_association_id']});
    var data = {};
    data['rubric[title]'] = vals.title;
    data['rubric[points_possible]'] = vals.rubric_total;
    data['rubric_association[use_for_grading]'] = $rubric.find(".grading_rubric_checkbox").attr('checked') ? "1" : "0";
    data['rubric_association[hide_score_total]'] = "0";
    if(data['rubric_association[use_for_grading]'] == '0') {
      data['rubric_association[hide_score_total]'] = $rubric.find(".totalling_rubric_checkbox").attr('checked') ? "1" : "0";
    }
    data['rubric[free_form_criterion_comments]'] = $rubric.find(".rubric_custom_rating").attr('checked') ? "1" : "0";
    data['rubric_association[id]'] = vals.rubric_association_id;
    var criterion_idx = 0;
    $rubric.find(".criterion:not(.blank)").each(function() {
      var $criterion = $(this);
      if(!$criterion.hasClass('learning_outcome_criterion')) {
        $criterion.find("span.mastery_points").text(parseFloat($criterion.find("input.mastery_points").val(), 10) || "0");
      }
      var vals = $criterion.getTemplateData({textValues: ['description', 'display_criterion_points', 'learning_outcome_id', 'mastery_points', 'long_description', 'criterion_id']});
      vals.long_description = $criterion.find("textarea.long_description").val();
      vals.mastery_points = $criterion.find("span.mastery_points").text();
      var pre_criterion = "rubric[criteria][" + criterion_idx + "]";
      data[pre_criterion + "[description]"] = vals.description;
      data[pre_criterion + "[points]"] = vals.display_criterion_points;
      data[pre_criterion + "[learning_outcome_id]"] = vals.learning_outcome_id;
      data[pre_criterion + "[long_description]"] = vals.long_description;
      data[pre_criterion + "[id]"] = vals.criterion_id;
      if(vals.learning_outcome_id) {
        data[pre_criterion + "[mastery_points]"] = vals.mastery_points;
      }
      var rating_idx = 0;
      $criterion.find(".rating").each(function() {
        var $rating = $(this);
        var vals = $rating.getTemplateData({textValues: ['description', 'points', 'rating_id']});
        var pre_rating = pre_criterion + "[ratings][" + rating_idx + "]";
        data[pre_rating + "[description]"] = vals.description;
        data[pre_rating + "[points]"] = vals.points;
        data[pre_rating + "[id]"] = vals.rating_id;
        rating_idx++;
      });
      criterion_idx++;
    });
    data.title = data['rubric[title]'];
    data.points_possible = data['rubric[points_possible]'];
    data.rubric_id = $rubric.attr('id').substring(7);
    data = $.extend(data, $("#rubrics #rubric_parameters").getFormData());
    return data;
  },
  addRubric: function() {
    var $rubric = $("#default_rubric").clone(true).attr('id', 'rubric_new').addClass('editing');
    $rubric.find("#edit_rubric").remove();
    var $tr = $("#edit_rubric").clone(true).show().removeAttr('id').addClass('edit_rubric');
    var $form = $tr.find("#edit_rubric_form");
    $rubric.append($tr);
    $form.attr('method', 'POST').attr('action', $("#add_rubric_url").attr('href'));
    var assignment_points = parseFloat($("#full_assignment .points_possible,#rubrics.rubric_dialog .assignment_points_possible").filter(":first").text());
    $form.find(".rubric_grading").showIf(assignment_points || $("#full_assignment").length > 0);
    return $rubric;
  },
  editRubric: function($original_rubric, url) {
    var $rubric = $original_rubric.clone(true).addClass('editing');
    $rubric.find("#edit_rubric").remove();
    var data = $rubric.getTemplateData({textValues: ['use_for_grading', 'free_form_criterion_comments', 'hide_score_total']});
    $original_rubric.hide().after($rubric.show());
    var $tr = $("#edit_rubric").clone(true).show().removeAttr('id').addClass('edit_rubric');
    var $form = $tr.find("#edit_rubric_form");
    $rubric.append($tr);
    $rubric.find(":text:first").focus().select();
    $form.find(".grading_rubric_checkbox").attr('checked', data.use_for_grading == "true").triggerHandler('change');
    $form.find(".rubric_custom_rating").attr('checked', data.free_form_criterion_comments == "true").triggerHandler('change');
    $form.find(".totalling_rubric_checkbox").attr('checked', data.hide_score_total == "true").triggerHandler('change');
    $form.find(".save_button").text($rubric.attr('id') == 'rubric_new' ? "Create Rubric" : "Update Rubric");
    $form.attr('method', 'PUT').attr('action', url);
    rubricEditing.sizeRatings();
    return $rubric;
  },
  hideEditRubric: function($rubric, remove) {
    $rubric = $rubric.filter(":first");
    if(!$rubric.hasClass('editing')) {
      $rubric = $rubric.next(".editing");
    }
    $rubric.removeClass('editing');
    $("#edit_criterion").hide().appendTo('body');
    $rubric.find(".edit_rubric").remove();
    if(remove) {
      if($rubric.attr('id') != 'rubric_new') {
        $rubric.prev(".rubric").show();
      } else {
        $(".add_rubric_link").show();
      }
      $rubric.remove();
    } else {
      $rubric.find(".rubric_title .links").show();
    }
  },
  updateRubric: function($rubric, rubric) {
    $rubric.find(".criterion:not(.blank)").remove();
    var $rating_template = $rubric.find(".rating:first").clone(true).removeAttr('id');
    $rubric.fillTemplateData({
      data: rubric,
      id: "rubric_" + rubric.id,
      hrefValues: ['id', 'rubric_association_id'],
      avoid: '.criterion'
    });
    $rubric.fillFormData(rubric);
    var url = $.replaceTags($rubric.find(".edit_rubric_url").attr('href'), 'rubric_id', rubric.id);
    $rubric.find(".edit_rubric_link").attr('href', url);
    var url = $.replaceTags($rubric.find(".delete_rubric_url").attr('href'), 'association_id', rubric.rubric_association_id);
    $rubric.find(".delete_rubric_link").attr('href', url);
    $rubric.find(".edit_rubric_link").showIf(rubric.permissions.update_association);
    $rubric.find(".find_rubric_link").showIf(rubric.permissions.update_association && !$("#rubrics").hasClass('raw_listing'));
    $rubric.find(".delete_rubric_link").showIf(rubric.permissions['delete_association']);
    $rubric.find(".criterion:not(.blank) .ratings").empty();
    for(var idx in rubric.criteria) {
      var criterion = rubric.criteria[idx];
      criterion.display_criterion_points = criterion.points;
      criterion.criterion_id = criterion.id;
      var $criterion = $rubric.find(".criterion.blank:first").clone(true).show().removeAttr('id');
      $criterion.removeClass('blank');
      $criterion.fillTemplateData({data: criterion});
      $criterion.find(".long_description_holder").toggleClass('empty', !criterion.long_description);
      $criterion.find(".ratings").empty();
      $criterion.toggleClass('learning_outcome_criterion', !!criterion.learning_outcome_id);
      for(var jdx in criterion.ratings) {
        var rating = criterion.ratings[jdx];
        rating.rating_id = rating.id;
        var $rating = $rating_template.clone(true);
        $rating.toggleClass('edge_rating', jdx === 0 || jdx === criterion.ratings.length - 1);
        $rating.fillTemplateData({data: rating});
        $criterion.find(".ratings").append($rating);
      }
      $rubric.find(".summary").before($criterion);
      $criterion.find(".criterion_points").val(criterion.points).blur();
    }
    $rubric.find(".criterion:not(.blank)")
      .find(".ratings").showIf(!rubric.free_form_criterion_comments).end()
      .find(".custom_ratings").showIf(rubric.free_form_criterion_comments);
  }
};
rubricEditing.sizeRatings = $.debounce(10, rubricEditing.originalSizeRatings);

$(document).ready(function() {
  var limitToOneRubric = true;
  var $rubric_dialog = $("#rubric_dialog"),
      $rubric_long_description_dialog = $("#rubric_long_description_dialog");
  
  rubricEditing.htmlBody = $('html,body');
      
  $("#rubrics")
  .delegate(".long_description_link", 'click', function(event) {
    event.preventDefault();
    var editing    = $(this).parents(".rubric").hasClass('editing'),
        $criterion = $(this).parents(".criterion"),
        data       = $criterion.getTemplateData({textValues: ['long_description', 'description']});
    data.long_description = $criterion.find("textarea.long_description").val();
    $rubric_long_description_dialog
      .data('current_criterion', $criterion)
      .fillTemplateData({data: data, htmlValues: ['long_description']})
      .fillFormData(data)
      .find(".editing").showIf(editing && !$criterion.hasClass('learning_outcome_criterion')).end()
      .find(".displaying").showIf(!editing || $criterion.hasClass('learning_outcome_criterion')).end()
      .dialog('close').dialog({
        autoOpen: false,
        title: "Criterion Long Description",
        width: 400
      }).dialog('open')
      .find("textarea:visible:first").focus().select();
    
  })
  .delegate(".find_rubric_link", 'click', function(event) {
    event.preventDefault();
    $rubric_dialog.dialog('close').dialog({
      autoOpen: true,
      width: 800,
      height: 380,
      resizable: true,
      title: 'Find Existing Rubric'
    }).dialog('open');
    if(!$rubric_dialog.hasClass('loaded')) {
      $rubric_dialog.find(".loading_message").text("Loading rubric groups...");
      var url = $rubric_dialog.find(".grading_rubrics_url").attr('href');
      $.ajaxJSON(url, 'GET', {}, function(data) {
        for(var idx in data) {
          var context = data[idx];
          var $context = $rubric_dialog.find(".rubrics_dialog_context_select.blank:first").clone(true).removeClass('blank');
          $context.fillTemplateData({
            data: {
              name: context.name,
              context_code: context.context_code,
              rubrics: context.rubrics + " rubrics"
            }
          });
          $rubric_dialog.find(".rubrics_dialog_contexts_select").append($context.show());
        }
        var codes = {};
        if(data.length == 0) {
          $rubric_dialog.find(".loading_message").text("No rubrics found");
        } else {
          $rubric_dialog.find(".loading_message").remove();
        }
        $rubric_dialog.find(".rubrics_dialog_rubrics_holder").slideDown();
        $rubric_dialog.find(".rubrics_dialog_contexts_select .rubrics_dialog_context_select:visible:first").click();
        $rubric_dialog.addClass('loaded');
      }, function(data) {
        $rubric_dialog.find(".loading_message").text("Loading rubrics failed, please try again");
      });
    }
  })
  .delegate(".edit_rubric_link", 'click', function(event) {
    var $this = $(this);
    if ( 
      !$this.hasClass('copy_edit')  || 
      confirm("You can't edit this rubric, either because you don't have permission or it's being used in more than one place. Any changes you make will result in a new rubric based on the old rubric.  Continue anyway?")
    ) {
      rubricEditing.editRubric($this.parents(".rubric"), $this.attr('href')); //.hide().after($rubric.show());
    }
    return false;
  });
  
  // cant use delegate because events bound to a .delegate wont get triggered when you do .triggerHandler('click') because it wont bubble up.
  $(".rubric .delete_rubric_link").bind('click', function(event, callback) {
    event.preventDefault();
    var message = "Are you sure you want to delete this rubric?";
    if(callback && callback.confirmationMessage) {
      message = callback.confirmationMessage;
    }
    $(this).parents(".rubric").confirmDelete({ 
      url: $(this).attr('href'),
      message: message,
      success: function() {
        $(this).fadeOut(function() {
          $(".add_rubric_link").show();
          if(callback && $.isFunction(callback)) {
            callback();
          }
        });
      }
    });
  });
  
  $rubric_long_description_dialog.find(".save_button").click(function() {
    var long_description = $rubric_long_description_dialog.find("textarea.long_description").val(),
        $criterion       = $rubric_long_description_dialog.data('current_criterion');
    if($criterion) {
      $criterion.fillTemplateData({data: {long_description: long_description}});
      $criterion.find("textarea.long_description").val(long_description);
      $criterion.find(".long_description_holder").toggleClass('empty', !long_description);
    }
    $rubric_long_description_dialog.dialog('close');
  });
  $rubric_long_description_dialog.find(".cancel_button").click(function() {
    $rubric_long_description_dialog.dialog('close');
  });
  
  $(".add_rubric_link").click(function(event) {
    event.preventDefault();
    if($("#rubric_new").length > 0) { return; }
    if(limitToOneRubric && $("#rubrics .rubric:visible").length > 0) { return; }
    var $rubric = rubricEditing.addRubric();
    $("#rubrics").append($rubric.show());
    $rubric.find(":text:first").focus().select();
    if(limitToOneRubric) {
      $(".add_rubric_link").hide();
    }
  });

  $("#rubric_dialog")
  .delegate(".rubrics_dialog_context_select", 'click', function(event) {
    event.preventDefault();
    $(".rubrics_dialog_contexts_select .selected_side_tab").removeClass('selected_side_tab');
    var $link = $(this);
    $link.addClass('selected_side_tab');
    var context_code = $link.getTemplateData({textValues: ['context_code']}).context_code;
    if($link.hasClass('loaded')) {
      $rubric_dialog.find(".rubrics_loading_message").hide();
      $rubric_dialog.find(".rubrics_dialog_rubrics,.rubrics_dialog_rubrics_select").show();
      $rubric_dialog.find(".rubrics_dialog_rubrics_select .rubrics_dialog_rubric_select").hide();
      $rubric_dialog.find(".rubrics_dialog_rubrics_select .rubrics_dialog_rubric_select." + context_code).show();
      $rubric_dialog.find(".rubrics_dialog_rubrics_select .rubrics_dialog_rubric_select:visible:first").click();
    } else {
      $rubric_dialog.find(".rubrics_loading_message").text("Loading rubrics...").show();
      $rubric_dialog.find(".rubrics_dialog_rubrics,.rubrics_dialog_rubrics_select").hide();
      var url = $rubric_dialog.find(".grading_rubrics_url").attr('href') + "?context_code=" + context_code;
      $.ajaxJSON(url, 'GET', {}, function(data) {
        $link.addClass('loaded');
        $rubric_dialog.find(".rubrics_loading_message").hide();
        $rubric_dialog.find(".rubrics_dialog_rubrics,.rubrics_dialog_rubrics_select").show();
        for(var idx in data) {
          var association = data[idx].rubric_association;
          var rubric = association.rubric;
          var $rubric_select = $rubric_dialog.find(".rubrics_dialog_rubric_select.blank:first").clone(true);
          $rubric_select.addClass(association.context_code);
          rubric.criterion_count = rubric.data.length;
          $rubric_select.fillTemplateData({data: rubric}).removeClass('blank');
          $rubric_dialog.find(".rubrics_dialog_rubrics_select").append($rubric_select.show());
          var $rubric = $rubric_dialog.find(".rubrics_dialog_rubric.blank:first").clone(true);
          $rubric.removeClass('blank');
          $rubric.find(".criterion.blank").hide();
          rubric.rubric_total = rubric.points_possible;
          $rubric.fillTemplateData({
            data: rubric,
            id: 'rubric_dialog_' + rubric.id
          });
          for(var idx in rubric.data) {
            var criterion = rubric.data[idx];
            criterion.criterion_points = criterion.points;
            criterion.criterion_points_possible = criterion.points;
            criterion.criterion_description = criterion.description;
            var ratings = criterion['ratings'];
            delete criterion['ratings'];
            var $criterion = $rubric.find(".criterion.blank:first").clone().removeClass('blank');
            $criterion.fillTemplateData({
              data: criterion
            });
            $criterion.find(".rating_holder").addClass('blank');
            for(var jdx in ratings) {
              var rating = ratings[jdx];
              var $rating = $criterion.find(".rating_holder.blank:first").clone().removeClass('blank');
              rating.rating = rating.description;
              $rating.fillTemplateData({
                data: rating
              });
              $criterion.find(".ratings").append($rating.show());
            }
            $criterion.find(".rating_holder.blank").remove();
            $rubric.find(".rubric.rubric_summary tr.summary").before($criterion.show());
          }
          $rubric_dialog.find(".rubrics_dialog_rubrics").append($rubric);
        }
        $rubric_dialog.find(".rubrics_dialog_rubrics_select .rubrics_dialog_rubric_select").hide();
        $rubric_dialog.find(".rubrics_dialog_rubrics_select .rubrics_dialog_rubric_select." + context_code).show();
        $rubric_dialog.find(".rubrics_dialog_rubrics_select .rubrics_dialog_rubric_select:visible:first").click();
      }, function(data) {
        $rubric_dialog.find(".rubrics_loading_message").text("Loading rubrics failed, please try again");
      });
    }
  })
  .delegate(".rubrics_dialog_rubric_select", 'click', function(event) {
    event.preventDefault();
    var $select = $(this);
    $select.find("a").focus();
    var id = $select.getTemplateData({textValues: ['id']}).id;
    $(".rubric_dialog .rubrics_dialog_rubric_select").removeClass('selected_side_tab'); //.css('fontWeight', 'normal');
    $select.addClass('selected_side_tab');
    $(".rubric_dialog .rubrics_dialog_rubric").hide();
    $(".rubric_dialog #rubric_dialog_" + id).show();
  })
  .delegate(".select_rubric_link", 'click', function(event) {
    event.preventDefault();
    var data = {};
    var params = $rubric_dialog.getTemplateData({textValues: ['rubric_association_type', 'rubric_association_id', 'rubric_association_purpose']});
    data['rubric_association[association_type]'] = params.rubric_association_type;
    data['rubric_association[association_id]'] = params.rubric_association_id;
    data['rubric_association[rubric_id]'] = $(this).parents(".rubrics_dialog_rubric").getTemplateData({textValues: ['id']}).id;
    data['rubric_association[purpose]'] = params.rubric_association_purpose;
    $rubric_dialog.loadingImage();
    var url = $rubric_dialog.find(".select_rubric_url").attr('href');
    $.ajaxJSON(url, 'POST', data, function(data) {
      $rubric_dialog.loadingImage('remove');
      var $rubric = $("#rubrics .rubric:visible:first");
      if($rubric.length === 0) {
        $rubric = rubricEditing.addRubric();
      }
      var rubric = data.rubric;
      rubric.rubric_association_id = data.rubric_association.id;
      rubric.permissions = rubric.permissions || {};
      if(data.rubric_association.permissions) {
        rubric.permissions.update_association = data.rubric_association.permissions.update;
        rubric.permissions.delete_association = data.rubric_association.permissions['delete'];
      }
      rubricEditing.updateRubric($rubric, rubric);
      rubricEditing.hideEditRubric($rubric, false);
      $rubric_dialog.dialog('close');
    }, function() {
      $rubric_dialog.loadingImage('remove');
    });
  });
  
  $rubric_dialog.find(".cancel_find_rubric_link").click(function(event) {
    event.preventDefault();
    $rubric_dialog.dialog('close');
  });
  $rubric_dialog.find(".rubric_brief").find(".expand_data_link,.collapse_data_link").click(function(event) {
    event.preventDefault();
    $(this).parents(".rubric_brief").find(".expand_data_link,.collapse_data_link").toggle().end()
      .find(".details").slideToggle();
  });
  $("#edit_rubric_form").formSubmit({
    processData: function(data) {
      var $rubric = $(this).parents(".rubric");
      if($rubric.find(".criterion:not(.blank)").length === 0) { return false; }
      var data = rubricEditing.rubricData($rubric);
      if(data['rubric_association[use_for_grading]'] == '1') {
        var assignment_points = parseFloat($("#full_assignment .points_possible").text());
        var rubric_points = parseFloat(data.points_possible);
        if(assignment_points && rubric_points != assignment_points) {
          var result = confirm("The points total does not match the assignment's points.  Do you want to change the assignment's points to match the rubric score?");
          if(result) {
          } else {
            return false;
          }
        }
      }
      return data;
    },
    beforeSubmit: function(data) {
      var $rubric = $(this).parents(".rubric");
      $rubric.find("thead .title").text(data['rubric[title]']);
      $rubric.find(".rubric_total").text(data['points_possible']);
      $rubric.removeClass('editing');
      if($rubric.attr('id') == 'rubric_new') {
        $rubric.attr('id', 'rubric_adding');
      } else {
        $rubric.prev(".rubric").remove();
      }
      $(this).parents("tr").hide();
      $rubric.loadingImage();
      return $rubric;
    },
    success: function(data, $rubric) {
      var rubric = data.rubric;
      $rubric.loadingImage('remove');
      rubric.rubric_association_id = data.rubric_association.id;
      rubric.permissions = rubric.permissions || {};
      if(data.rubric_association.permissions) {
        rubric.permissions.update_association = data.rubric_association.permissions.update;
        rubric.permissions.delete_association = data.rubric_association.permissions['delete'];
      }
      rubricEditing.updateRubric($rubric, rubric);
      if(data.rubric_association && data.rubric_association.use_for_grading) {
        $("#full_assignment .points_possible").text(rubric.points_possible);
        $("#full_assignment input.points_possible").val(rubric.points_possible);
      }
      $rubric.find(".rubric_title .links:not(.locked)").show();
    }
  });

  $("#edit_rubric_form .cancel_button").click(function() {
    rubricEditing.hideEditRubric($(this).parents(".rubric"), true);
  });

  $("#rubrics").delegate('.add_criterion_link', 'click', function(event) {
    var $criterion = rubricEditing.addCriterion($(this).parents(".rubric")); //"#default_rubric"));
    rubricEditing.editCriterion($criterion);
    return false;
  }).delegate('.find_outcome_link', 'click', function(event) {
    rubricEditing.findOutcomeCriterion($(this).parents(".rubric"));
    return false;
  }).delegate('.criterion_description_value', 'click', function(event) {
    rubricEditing.editCriterion($(this).parents(".criterion"));
    return false;
  }).delegate('.edit_criterion_link', 'click', function(event) {
    rubricEditing.editCriterion($(this).parents(".criterion"));
    return false;
  }).delegate('.delete_criterion_link', 'click', function(event) {
    var $criterion = $(this).parents(".criterion");
    $criterion.fadeOut(function() {
      var $rubric = $criterion.parents(".rubric");
      $criterion.remove();
      rubricEditing.updateCriteria($rubric);
      rubricEditing.updateRubricPoints($rubric);
    });
    return false;
  }).delegate('.rating_description_value,.edit_rating_link', 'click', function(event) {
    rubricEditing.editRating($(this).parents(".rating"));
    return false;
  }).bind('mouseover', function(event) {
    $target = $(event.target);
    if(!$target.closest('.ratings').length) {
      rubricEditing.hideCriterionAdd($target.parents('.rubric'));
    }
  }).delegate('.rating', 'mousemove', function(event) {
    var $this   = $(this),
        $rubric = $this.parents(".rubric");
    if($rubric.find(".rating.editing").length > 0 || $this.parents(".criterion").hasClass('learning_outcome_criterion')) {
      rubricEditing.hideCriterionAdd($rubric);
      return false;
    }
    var expandPadding = 10;
    if(!$.data(this, 'hover_offset')) {
      $.data(this, 'hover_offset', $this.offset());
      $.data(this, 'hover_width', $this.outerWidth());
      var points = $.data(this, 'points', parseFloat($this.find(".points").text()));
      var prevPoints = $.data(this, 'prev_points', parseFloat($this.prev(".rating").find(".points").text()));
      var nextPoints = $.data(this, 'next_points', parseFloat($this.next(".rating").find(".points").text()));
      $.data(this, 'prev_diff', Math.abs(points - prevPoints));
      $.data(this, 'next_diff', Math.abs(points - nextPoints));
    }
    var offset = $.data(this, 'hover_offset');
    var width = $.data(this, 'hover_width');
    var $ratings = $this.parents(".ratings");
    var x = event.pageX;
    var y = event.pageY;
    var leftSide = false;
    if(x <= offset.left + (width / 2)) {
      leftSide = true;
    }
    var $lastHover = $ratings.data('hover_rating');
    var lastLeftSide = $ratings.data('hover_left_side');
    if(!$lastHover || $this[0] != $lastHover[0] || leftSide != lastLeftSide) {
      rubricEditing.hideCriterionAdd($rubric);
      var $prevRating, $nextRating;
      if(leftSide && ($prevRating = $this.prev(".rating")) && $prevRating.length) {// && $(this).data('prev_diff') > 1) {
        $this.addClass('add_left');
        $prevRating.addClass('add_right');
        $this[(x <= offset.left + expandPadding) ? 'addClass': 'removeClass']('add_column');
      } else if(!leftSide && ($nextRating = $this.next(".rating")) && $nextRating.length) {// && $(this).data('next_diff') > 1) {
        $this.addClass('add_right');
        $nextRating.addClass('add_left');
        $this[(x >= offset.left + width - expandPadding) ? 'addClass' : 'removeClass']('add_column');
      }
    } else if($lastHover) {
      if(leftSide) {
        if(x <= offset.left + expandPadding && $.data(this, 'prev_diff') > 1) {
          $this.addClass('add_column');
        } else {
          $this.removeClass('add_column');
        }
      } else {
        if(x >= offset.left + width - expandPadding && $.data(this, 'next_diff') > 1) {
          $this.addClass('add_column');
        } else {
          $this.removeClass('add_column');
        }
      }
    }
    return false;
  }).delegate('.rating', 'mouseout', function(event) {
    $(this).data('hover_offset', null).data('hover_width', null);
  }).delegate('.delete_rating_link', 'click', function(event) {
    event.preventDefault();
    rubricEditing.hideCriterionAdd($(this).parents(".rubric"));
    $(this).parents(".rating").fadeOut(function() {
      var $criterion = $(this).parents(".criterion");
      $(this).remove();
      rubricEditing.sizeRatings($criterion);
    });
  }).delegate('.add_column', 'click', function(event) {
    var $this = $(this),
        $rubric = $this.parents(".rubric"); 
    if($rubric.hasClass('editing')){
      var $td = $this.clone(true).removeClass('edge_rating'),
          pts = parseFloat($this.find(".points").text()),
          $criterion = $this.parents(".criterion"),
          $criterionPoints = $criterion.find(".criterion_points"),
          criterion_total = parseFloat($criterionPoints.val(), 10) || 5,
          data = { description: "Rating Description" },
          hasClassAddLeft = $this.hasClass('add_left');
      if($this.hasClass('add_left')) {
        var more_points = parseFloat($this.prev(".rating").find(".points").text());
        data.points = Math.round((pts + more_points) / 2);
        if(data.points == pts || data.points == more_points) {
          data.points = more_points;
          $criterion.find(".criterion_points").val(criterion_total + 1);
        }
      } else {
        var less_points = parseFloat($this.next(".rating").find(".points").text());
        data.points = Math.round((pts + less_points) / 2);
        if(data.points == pts || data.points == less_points) {
          data.points = pts;
          $criterionPoints.val(criterion_total + 1);
        }
      }
      $td.fillTemplateData({data: data});
      if(hasClassAddLeft) {
        $this.before($td);
      } else {
        $this.after($td);
      }
      rubricEditing.hideCriterionAdd($rubric);
      rubricEditing.updateCriterionPoints($criterion);
      rubricEditing.sizeRatings($criterion); 
    }
    return false;
  });
  $(".criterion_points").keydown(function(event) {
    if(event.keyCode == 13) {
      rubricEditing.updateCriterionPoints($(this).parents(".criterion"));
      $(this).blur();
    }
  }).blur(function(event) {
    rubricEditing.updateCriterionPoints($(this).parents(".criterion"));
  });
  $("#edit_criterion").delegate(".cancel_button", 'click', function(event) {
    rubricEditing.hideEditCriterion();
  });
  $("#edit_criterion_form").submit(function(event) {
    event.preventDefault();
    event.stopPropagation();
    var data = $(this).parents("#edit_criterion").getFormData();
    data.criterion_description_value = data.description;
    delete data['description'];
    $(this).parents(".criterion").fillTemplateData({data: data});
    rubricEditing.hideEditCriterion();
  });
  $("#edit_rating").delegate(".cancel_button", 'click', function(event) {
    rubricEditing.hideEditRating();
  });
  $("#edit_rating_form").submit(function(event) {
    event.preventDefault();
    event.stopPropagation();
    var data = $(this).parents("#edit_rating").getFormData();
    data.points = parseFloat(data.points);
    if(isNaN(data.points)) {
      data.points = parseFloat($(this).parents(".criterion").find(".criterion_points").val());
      if(isNaN(data.points)) { data.points = 5; }
    }
    var $rating = $(this).parents(".rating");
    $rating.fillTemplateData({data: data});
    if($rating.prev(".rating").length === 0) {
      $(this).parents(".criterion").find(".criterion_points").val(data.points);
    }
    rubricEditing.updateCriterionPoints($(this).parents(".criterion"), true);
  });
  $("#edit_rubric_form .rubric_custom_rating").change(function() {
    $(this).parents(".rubric").find("tr.criterion")
      .find(".ratings").showIf(!$(this).attr('checked')).end()
      .find(".custom_ratings").showIf($(this).attr('checked'));
  }).triggerHandler('change');
  $("#edit_rubric_form #totalling_rubric").change(function() {
    $(this).parents(".rubric").find(".total_points_holder").showIf(!$(this).attr('checked'));
  });
  $("#edit_rubric_form .grading_rubric_checkbox").change(function() {
    $(this).parents(".rubric").find(".totalling_rubric").css('visibility', $(this).attr('checked') ? 'hidden' : 'visible');
    $(this).parents(".rubric").find(".totalling_rubric_checkbox").attr('checked', false);
  }).triggerHandler('change');
  $("#criterion_blank").find(".criterion_points").val("5");
  if($("#default_rubric").find(".criterion").length <= 1) {
    rubricEditing.addCriterion($("#default_rubric"));
  }
  setInterval(rubricEditing.sizeRatings, 10000);
});
