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

var jsonData, visibleRubricAssessments;
var anonymousAssignment = false;
(function($, INST, scribd, rubricAssessment) {
  
  // fire off the request to get the jsonData,
  $.ajaxJSON(window.location.pathname+ '.json' + window.location.search, 'GET', {}, function(json) {
    window.jsonData = json;
    $(EG.jsonReady);
  });
  // ...and while we wait for that, get this stuff ready

  // PRIVATE VARIABLES AND FUNCTIONS
  // all of the $ variables here are to speed up access to dom nodes,
  // so that the jquery selector does not have to be run every time.
  // note, this assumes that this js file is being loaded at the bottom of the page
  // so that all these dom nodes already exists.  
  var $window = $(window),
      $body = $("body"),
      $full_width_container =$("#full_width_container"),
      $left_side = $("#left_side"),
      $right_side = $("#right_side"),
      $width_resizer = $("#width_resizer"),
      $gradebook_header = $("#gradebook_header"),
      assignmentUrl = $("#assignment_url").attr('href'),
      $full_height = $(".full_height"),
      $rightside_inner = $("#rightside_inner"),
      $comments = $("#comments"),
      $comment_blank = $("#comment_blank").removeAttr('id').detach(),
      $comment_attachment_blank = $("#comment_attachment_blank").removeAttr('id').detach(),
      $comment_media_blank = $("#comment_media_blank").removeAttr('id').detach(),
      $add_a_comment = $("#add_a_comment"),
      $add_a_comment_submit_button = $add_a_comment.find("button"),
      $add_a_comment_textarea = $add_a_comment.find("textarea"),
      $group_comment_wrapper = $("#group_comment_wrapper"),
      $comment_attachment_input_blank = $("#comment_attachment_input_blank").detach(),
      fileIndex = 1,
      $add_attachment = $("#add_attachment"),
      minimumWindowHeight = 500,
      $submissions_container = $("#submissions_container"),
      $iframe_holder = $("#iframe_holder"),
      $x_of_x_students = $("#x_of_x_students span"),
      $grded_so_far = $("#x_of_x_graded span:first"),
      $average_score = $("#average_score"),
      $this_student_does_not_have_a_submission = $("#this_student_does_not_have_a_submission").hide(),
      $scribd_doc_holder = $("#scribd_doc_holder"),
      $rubric_assessments_select = $("#rubric_assessments_select"),
      $rubric_summary_container = $("#rubric_summary_container"),
      $rubric_holder = $("#rubric_holder"),
      $grade_container = $("#grade_container"),
      $grade = $grade_container.find("input, select"),
      $score = $grade_container.find(".score"),
      $average_score_wrapper = $("#average_score_wrapper"),
      $submission_details = $("#submission_details"),
      $single_submission = $("#single_submission"),
      $single_submission_submitted_at = $("#single_submission_submitted_at"),
      $multiple_submissions = $("#multiple_submissions"),
      $submission_late_notice = $("#submission_late_notice"),
      $submission_not_newest_notice = $("#submission_not_newest_notice"),
      $submission_files_container = $("#submission_files_container"),
      $submission_files_list = $("#submission_files_list"),
      $submission_file_hidden = $("#submission_file_hidden").removeAttr('id').detach(),
      $submitted_files_plurality = $("#submitted_files_plurality"),
      $submission_to_view = $("#submission_to_view"),
      $assignment_submission_url = $("#assignment_submission_url"),
      $rubric_full = $("#rubric_full"),
      $rubric_full_resizer_handle = $("#rubric_full_resizer_handle"),
      $selectmenu = null,
      broswerableCssClasses = /^(image|html|code)$/,
      windowLastHeight = null,
      resizeTimeOut = null,
      iframes = {},
      snapshotCache = {},
      sectionToShow;
      
  function mergeStudentsAndSubmission(){
    jsonData.studentsWithSubmissions = jsonData.context.students;
    $.each(jsonData.studentsWithSubmissions, function(i, student){
      this.section_ids = $.map($.grep(jsonData.context.enrollments, function(enrollment, i){
          return enrollment.user_id === student.id;
        }), function(enrollment){ 
        return enrollment.course_section_id;
      });
      this.submission = $.grep(jsonData.submissions, function(submission, i){
        return submission.user_id === student.id;
      })[0];
      this.rubric_assessments = $.grep(visibleRubricAssessments, function(rubricAssessment, i){
        return rubricAssessment.user_id === student.id;
      });
    });
    
    // handle showing students only in a certain section.
    // the sectionToShow will be remembered for a given user in a given browser across all assignments in this course 
    sectionToShow = Number($.store.userGet("grading_show_only_section"+jsonData.context_id));
    if (sectionToShow) {
      var tempArray  = $.grep(jsonData.studentsWithSubmissions, function(student, i){
        return $.inArray(sectionToShow, student.section_ids) != -1;
      });
      if (tempArray.length) {
        jsonData.studentsWithSubmissions = tempArray;
      } else {
        alert("Could not find any students in that section, falling back to showing all sections.");
        $.store.userRemove("grading_show_only_section"+jsonData.context_id);
        window.location.reload();
      }
    }
    
    //by defaut the list is sorted alphbetically by student last name so we dont have to do any more work here, 
    // if the cookie to sort it by submitted_at is set we need to sort by submitted_at.
    var hideStudentNames;
    if ($.store.userGet("eg_hide_student_names") == "true") {
      hideStudentNames = true;
    }
    if(hideStudentNames) {
      jsonData.studentsWithSubmissions.sort(function(a,b){
        return ((a && a.submission && a.submission.id) || Number.MAX_VALUE) - 
               ((b && b.submission && b.submission.id) || Number.MAX_VALUE);
      });          
    } else if ($.store.userGet("eg_sort_by") == "submitted_at") {
      jsonData.studentsWithSubmissions.sort(function(a,b){
        return ((a && a.submission && a.submission.submitted_at && $.parseFromISO(a.submission.submitted_at).timestamp) || Number.MAX_VALUE) - 
               ((b && b.submission && b.submission.submitted_at && $.parseFromISO(b.submission.submitted_at).timestamp) || Number.MAX_VALUE);
      });          
    } else if ($.store.userGet("eg_sort_by") == "submission_status") {
      jsonData.studentsWithSubmissions.sort(function(a,b) {
        var states = {
          "not_graded": 1,
          "resubmitted": 2,
          "not_submitted": 3,
          "graded": 4
        };
        var stateA = submissionStateName(a.submission);
        var stateB = submissionStateName(b.submission);
        return states[stateA] - states[stateB];
      });
    }
  }

  function submissionStateName(submission) {
    if (submission && submission.workflow_state != 'unsubmitted' && (submission.submitted_at || !(typeof submission.grade == 'undefined'))) {
      if (typeof submission.grade == 'undefined' || submission.grade === null || submission.workflow_state == 'pending_review') {
        return "not_graded";
      } else if (submission.grade_matches_current_submission) {
        return "graded";
      } else {
        return "resubmitted";
      }
    } else {
      return "not_submitted";
    }
  }
  
  function classNameBasedOnStudent(student){
    var raw = submissionStateName(student.submission);
    var formatted = raw.replace("_", " ");
    if (raw === "resubmitted") {
      formatted = "graded, then resubmitted (" + $.parseFromISO(student.submission.submitted_at).datetime_formatted + ")";
    }
    return {raw: raw, formatted: formatted};
  }
  
  function initDropdown(){
    var hideStudentNames;
    
    if ($.store.userGet("eg_hide_student_names") == "true" || anonymousAssignment) {
      hideStudentNames = true;
    }
    $("#hide_student_names").attr('checked', hideStudentNames);
    var options = $.map(jsonData.studentsWithSubmissions, function(s, idx){
      var name = $.htmlEscape(s.name),
          className = classNameBasedOnStudent(s);

      if(hideStudentNames) {
        name = "Student " + (idx + 1);
      }

      return '<option value="' + s.id + '" class="' + className.raw + '">' + name + ' ---- ' + className.formatted +'</option>';
    }).join("");

    $selectmenu = $("<select id='students_selectmenu'>" + options + "</select>")
      .appendTo("#combo_box_container")
      .selectmenu({
        style:'dropdown',
        format: function(text){
          var parts = text.split(" ---- ");
          return '<span class="ui-selectmenu-item-header">' + $.htmlEscape(parts[0]) + '</span><span class="ui-selectmenu-item-footer">' + parts[1] + '</span>';
        },
        icons: [
          {find: '.graded'},
          {find: '.not_graded'},
          {find: '.not_submitted'},
          {find: '.resubmitted'}
        ]
      }).change(function(e){
        EG.handleStudentChanged();
      });
      
    if (jsonData.context.active_course_sections.length && jsonData.context.active_course_sections.length > 1) {
      var $selectmenu_list = $selectmenu.data('selectmenu').list,
          $menu = $("#section-menu");
          
          
      $menu.find('ul').append($.map(jsonData.context.active_course_sections, function(section, i){
        return '<li><a data-section-id="'+ section.id +'" href="#">'+ section.name  +'</a></li>';
      }).join(''));
            
      $menu.insertBefore($selectmenu_list).bind('mouseenter mouseleave', function(event){
        $(this)
          .toggleClass('ui-selectmenu-item-selected ui-selectmenu-item-focus ui-state-hover', event.type == 'mouseenter')
          .find('ul').toggle(event.type == 'mouseenter');
      })
      .find('ul')
        .hide()
        .menu()
        .delegate('a', 'click mousedown', function(){
          $.store[$(this).data('section-id') == 'all' ? 'userRemove' : 'userSet']("grading_show_only_section"+jsonData.context_id, $(this).data('section-id'));
          window.location.reload();
        });
      
      if (sectionToShow) {
        var text = $.map(jsonData.context.active_course_sections, function(section){
                      if (section.id == sectionToShow) { return section.name; }
                   }).join(', ');
        
        $("#section_currently_showing").text(text);
        $menu.find('ul li a')
          .removeClass('selected')
          .filter('[data-section-id='+ sectionToShow +']')
            .addClass('selected');
      }
      
      $selectmenu.selectmenu( 'option', 'open', function(){
        $selectmenu_list.find('li:first').css('margin-top', $selectmenu_list.find('li').height() + 'px'); 
        $menu.show().css({
          'left'   : $selectmenu_list.css('left'),
          'top'    : $selectmenu_list.css('top'),
          'width'  : $selectmenu_list.width() - ($selectmenu_list.hasScrollbar() && $.getScrollbarWidth()),
          'z-index': Number($selectmenu_list.css('z-index')) + 1 
        });
        
      }).selectmenu( 'option', 'close', function(){
        $menu.hide();
      });
    }
  }
  
  function initHeader(){
    $gradebook_header.find(".prev").click(function(e){
      e.preventDefault();
      EG.prev();
    });
    $gradebook_header.find(".next").click(function(e){
      e.preventDefault();
      EG.next();
    });

    $("#settings_form").submit(function(){
      $.store.userSet('eg_sort_by', $('#eg_sort_by').val());
      $.store.userSet('eg_hide_student_names', $("#hide_student_names").attr('checked').toString());
      $(this).find(".submit_button").attr('disabled', true).text("Saving Settings...");
      window.location.reload();
      return false;
    });
    $("#settings_link").click(function(e){
      $("#settings_form").dialog('close').dialog({
        modal: true,
        resizeable: false,
        width: 400
      })
      .dialog('open');
    });
  }
  
  function initCommentBox(){
    //initialize the auto height resizing on the textarea
    $('#add_a_comment textarea').elastic({
      callback: EG.resizeFullHeight
    });

    $(".media_comment_link").click(function(event) {
      event.preventDefault();
      $("#media_media_recording").show().find(".media_recording").mediaComment('create', 'audio', function(id, type) {
        $("#media_media_recording").data('comment_id', id).data('comment_type', type);
        EG.handleCommentFormSubmit();
      }, function() {
        EG.revertFromFormSubmit();
      }, true);
      EG.resizeFullHeight();
    });
    
    $("#media_recorder_container a").live('click', hideMediaRecorderContainer);

    // handle speech to text for browsers that can (right now only chrome)
    function browserSupportsSpeech(){
      var elem = document.createElement('input');
      var support = 'onwebkitspeechchange' in elem || 'speech' in elem;
      return support;
    }
    if (browserSupportsSpeech()) {
      $(".speech_recognition_link").click(function() {
          $('<input style="font-size: 30px;" speech x-webkit-speech />')
            .dialog({
              title: "Click the mic to record your comments",
              open: function(){
                $(this).width(100);
              }
            })
            .bind('webkitspeechchange', function(){
              $add_a_comment_textarea.val($(this).val());
              $(this).dialog('close').remove();
            });
          return false;
        })
        // show the li that contains the button because it is hidden from browsers that dont support speech
        .closest('li').show();
    }
  }
  
  function hideMediaRecorderContainer(){
    $("#media_media_recording").hide().removeData('comment_id').removeData('comment_type');
    EG.resizeFullHeight();
  }
  
  function isAssessmentEditableByMe(assessment){
    //if the assessment is mine or I can :manage_course then it is editable
    if (!assessment || assessment.assessor_id === rubricAssessment.assessor_id ||
         (rubricAssessment.assessment_type == 'grading' && assessment.assessment_type == 'grading')
       ){
          return true;
    }
    return false;
  }
  
  function getSelectedAssessment(){
    return $.grep(EG.currentStudent.rubric_assessments, function(n,i){
      return n.id == $rubric_assessments_select.val();
    })[0];
  }
  
  function initRubricStuff(){

    $("#rubric_summary_container .button-container").appendTo("#rubric_assessments_list_and_edit_button_holder").find('.edit').text("Edit/View Rubric");

    $(".toggle_full_rubric, .hide_rubric_link").click(function(e){
      e.preventDefault();
      EG.toggleFullRubric();
    });

    $rubric_assessments_select.change(function(){
      var selectedAssessment = getSelectedAssessment();
      rubricAssessment.populateRubricSummary($("#rubric_summary_holder .rubric_summary"), selectedAssessment, isAssessmentEditableByMe(selectedAssessment));
      EG.resizeFullHeight();
    });

    $rubric_full_resizer_handle.draggable({
      axis: 'x',
      cursor: 'crosshair',
      scroll: false,
      containment: '#left_side',
      snap: '#full_width_container',
      appendTo: '#full_width_container',
      start: function(){
        $rubric_full_resizer_handle.draggable( 'option', 'minWidth', $right_side.width() );
      },
      helper: function(){
        return $rubric_full_resizer_handle.clone().addClass('clone');
      },
      drag: function(event, ui) {
        var offset = ui.offset,
            windowWidth = $window.width();
        $rubric_full.width(windowWidth - offset.left);
        $rubric_full_resizer_handle.css("left","0");
        EG.resizeFullHeight();
      },
      stop: function(event, ui) {
        event.stopImmediatePropagation();
      }
    });

    $(".save_rubric_button").click(function() {
      var $rubric = $(this).parents("#rubric_holder").find(".rubric");
      var data = rubricAssessment.assessmentData($rubric);
      var url = $(".update_rubric_assessment_url").attr('href');
      var method = "POST";
      EG.toggleFullRubric();
      $(".rubric_summary").loadingImage();
      $.ajaxJSON(url, method, data, function(response) {
        var found = false;
        if(response && response.rubric_association) {
          rubricAssessment.updateRubricAssociation($rubric, response.rubric_association);
          delete response.rubric_association;
        }
        for (var i in EG.currentStudent.rubric_assessments) {
          if (response.id === EG.currentStudent.rubric_assessments[i].id) {
            EG.currentStudent.rubric_assessments[i] = response;
            found = true;
            continue;
          }
        }
        if (!found) {
          EG.currentStudent.rubric_assessments.push(response);
        }
        
        // if this student has a submission, update it with the data returned, otherwise we need to create a submission for them
        EG.setOrUpdateSubmission(response.artifact);
        
        // this next part will take care of group submissions, so that when one member of the group gets assessesed then everyone in the group will get that same assessment.
        $.each(response.related_group_submissions_and_assessments, function(i,submissionAndAssessment){
          //setOrUpdateSubmission returns the student. so we can set student.rubric_assesments
          // submissionAndAssessment comes back with :include_root => true, so we have to get rid of the root
          EG.setOrUpdateSubmission(response.artifact).rubric_assessments = $.map(submissionAndAssessment.rubric_assessments, function(ra){return ra.rubric_assessment;});
        });
        
        $(".rubric_summary").loadingImage('remove');
        EG.showGrade();
    	  EG.showDiscussion();
    	  EG.showRubric();
    	  EG.updateStatsInHeader();
      });
    });
  }
  
  function initKeyCodes(){
    $window.keycodes({keyCodes: "j k p n c r g", ignore: 'input, textarea, embed, object'}, function(event) {
      event.preventDefault();
      event.stopPropagation();

      //Prev()
      if(event.keyString == "j" || event.keyString == "p") {
        EG.prev();
      }
      //next()
      else if(event.keyString == "k" || event.keyString == "n") {
        EG.next();
      }
      //comment
      else if(event.keyString == "f" || event.keyString == "c") {
        $add_a_comment_textarea.focus();
      }
      // focus on grade
      else if(event.keyString == "g") {
        $grade.focus();
      }
      // focus on rubric
      else if(event.keyString == "r") {
        EG.toggleFullRubric();
      }
    });
    $(window).shake($.proxy(EG.next, EG));
  }
  
  function resizingFunction(){
    var windowHeight = $window.height(),
        delta,
        deltaRemaining,
        headerOffset = $right_side.offset().top,
        fullHeight = Math.max(minimumWindowHeight, windowHeight) - headerOffset,
        resizableElements = [
          { element: $submission_files_list,    data: { newHeight: 0 } },
          { element: $rubric_summary_container, data: { newHeight: 0 } },
          { element: $comments,                 data: { newHeight: 0 } }
        ],
        visibleResizableElements = $.grep(resizableElements, function(e, i){
          return e && e.element.is(':visible');
        });
    $rubric_full.css({ 'maxHeight': fullHeight - 50, 'overflow': 'auto' });

    $.each(visibleResizableElements, function(){
      this.data.autoHeight = this.element.height("auto").height();
      this.element.height(0);
    });

    var spaceLeftForResizables = fullHeight - $rightside_inner.height("auto").height() - $add_a_comment.outerHeight();

    $full_height.height(fullHeight);
    delta = deltaRemaining = spaceLeftForResizables;
    var step = 1;
    var didNothing;
    if (delta > 0) { //the page got bigger
      while(deltaRemaining > 0){
        didNothing = true;
        var shortestElementHeight = 10000000;
        var shortestElement = null;
        $.each(visibleResizableElements, function(){
          if (this.data.newHeight < shortestElementHeight && this.data.newHeight < this.data.autoHeight) {
            shortestElement = this;
            shortestElementHeight = this.data.newHeight;
          }
        });
        if (shortestElement) {
          // console.log("grew", shortestElement, "by", step)
          shortestElement.data.newHeight = shortestElementHeight + step;
          deltaRemaining = deltaRemaining - step;
          didNothing = false;
        }
        if (didNothing) {
          // console.log("couldn't find shorter. deltaRemaining:", deltaRemaining) ;
          break;
        }
      }
    }
    else { //the page got smaller
      var tallestElementHeight, tallestElement;
      while(deltaRemaining < 0){
        didNothing = true;
        tallestElementHeight = 0;
        tallestElement = null;
        $.each(visibleResizableElements, function(){
          if (this.data.newHeight > 30 > tallestElementHeight && this.data.newHeight >= this.data.autoHeight ) {
            tallestElement = this;
            tallestElementHeight = this.data.newHeight;
          }
        });
        if (tallestElement) {
          tallestElement.data.newHeight = tallestElementHeight - step;
          deltaRemaining = deltaRemaining + step;
          didNothing = false;
        }
        if (didNothing) {
          // console.log('no elements without scrollbars:', deltaRemaining)
          break;
        }
      }
    }

    $.each(visibleResizableElements, function(){
      this.element.height(this.data.newHeight);
    });

    if (deltaRemaining > 0) {
      $comments.height( windowHeight - Math.floor($comments.offset().top) - $add_a_comment.outerHeight() );
    }
    // This will cause the page to flicker in firefox if there is a scrollbar in both the comments and the rubric summary.
    // I would like it not to, I tried setTimeout(function(){ $comments.scrollTop(1000000); }, 800); but that still doesnt work
    if(!INST.browser.ff && $comments.height() > 100) {
      $comments.scrollTop(1000000);
    }
  }

  $.extend(INST, {
    refreshGrades: function(){
      var url = unescape($assignment_submission_url.attr('href')).replace("{{submission_id}}", EG.currentStudent.submission.user_id) + ".json";
      $.getJSON( url,
        function(data){
          EG.currentStudent.submission = data.submission;
          EG.showGrade();
      });
    },
    refreshQuizSubmissionSnapshot: function(data) {
      snapshotCache[data.user_id + "_" + data.version_number] = data;
      if(data.last_question_touched) {
        INST.lastQuestionTouched = data.last_question_touched;
      }
    },
    clearQuizSubmissionSnapshot: function(data) {
      snapshotCache[data.user_id + "_" + data.version_number] = null;
    },
    getQuizSubmissionSnapshot: function(user_id, version_number) {
      return snapshotCache[user_id + "_" + version_number];
    }
  });

  window.onbeforeunload = function() {
    window.opener && window.opener.updateGrades && $.isFunction(window.opener.updateGrades) && window.opener.updateGrades();
     
    var userNamesWithPendingQuizSubmission = $.map(snapshotCache, function(snapshot) { 
      return snapshot && $.map(jsonData.context.students, function(student) {
        return (snapshot == student) && student.name;
      })[0]; 
    });
    
    if (userNamesWithPendingQuizSubmission.length) {
      return "The following students have unsaved changes to their quiz submissions: \n\n " +
              userNamesWithPendingQuizSubmission.join('\n ') +
              "\nContinue anyway?";
    }
  };

  // Public Variables and Methods
  var EG = {
    options: {},
    publicVariable: [],
    scribdDoc: null,
    currentStudent: null,
    
    domReady: function(){
      //attach to window resize and
      $window.bind('resize orientationchange', EG.resizeFullHeight).resize();

      function makeFullWidth(){
        $full_width_container.addClass("full_width");
        $left_side.css("width",'');
        $right_side.css("width",'');
      }

      $width_resizer.draggable({
        axis: 'x',
        cursor: 'crosshair',
        scroll: false,
        containment: '#full_width_container',
        snap: '#full_width_container',
        appendTo: '#full_width_container',
        helper: function(){
          return $width_resizer.clone().addClass('clone');
        },
        snapTolerance: 200,
        drag: function(event, ui) {
          var offset = ui.offset,
              windowWidth = $window.width();
          $left_side.width(offset.left / windowWidth * 100 + "%" );
          $right_side.width(100 - offset.left / windowWidth  * 100 + '%' );
          $width_resizer.css("left","0");
          if (windowWidth - offset.left < $(this).draggable('option', 'snapTolerance') ) {
            makeFullWidth();
          }
          else {
            $full_width_container.removeClass("full_width");
          }
          if (offset.left < $(this).draggable('option', 'snapTolerance')) {
            $left_side.width("0%" );
            $right_side.width('100%');
          }
          EG.resizeFullHeight();
        },
        stop: function(event, ui) {
          event.stopImmediatePropagation();
        }
      }).click(function(event){
          event.preventDefault();
          if ($full_width_container.hasClass("full_width")) {
            $full_width_container.removeClass("full_width");
          }
          else {
            makeFullWidth();
            // $(this).animate({backgroundColor: '#DCECFB'}, 500).animate({backgroundColor: '#bbbbbb'}, 1500);
            $(this).addClass('highlight', 100, function(){
              $(this).removeClass('highlight', 4000);
            });
          }
      });

      $grade.change(EG.handleGradeSubmit);

      $submission_to_view.change(function(){
        EG.currentStudent.submission.currentSelectedIndex = parseInt($(this).val(), 10);
        EG.handleSubmissionSelectionChange();
      });
      
      initRubricStuff();
      initCommentBox();
      EG.initComments();
      initHeader();
      initKeyCodes();

      $window.bind('hashchange', EG.handleFragementChange);
      $('#eg_sort_by').val($.store.userGet('eg_sort_by'));
      $('#submit_same_score').click(function(e) {
        EG.handleGradeSubmit();
        e.preventDefault();
      });
      
    },

    jsonReady: function(){
      //this runs after the request to get the jsonData comes back
      $("#speed_grader_loading").hide();
      $("#gradebook_header, #full_width_container").show();

      mergeStudentsAndSubmission();
      initDropdown();
      EG.handleFragementChange();
    },

    skipRelativeToCurrentIndex: function(offset){
      var newIndex = (this.currentIndex() + offset+ jsonData.studentsWithSubmissions.length) % jsonData.studentsWithSubmissions.length;
      this.goToStudent(jsonData.studentsWithSubmissions[newIndex].id);
    },

    next: function(){
      this.skipRelativeToCurrentIndex(1);
    },

    prev: function(){
      this.skipRelativeToCurrentIndex(-1);
    },

    resizeFullHeight: function(){
      if (resizeTimeOut) {
        clearTimeout(resizeTimeOut);
      }
      resizeTimeOut = setTimeout(resizingFunction, 0);
    },

    //args should be an object that looks like {"access_key": "key-20j3kkkct0fyyoar5luo" , doc_id: "15661305"}
    loadScribdDoc: function(args){
      var sd = this.scribdDoc = scribd.Document.getDoc( args.doc_id, args.access_key );

        $.each({
            'jsapi_version': 1,
            'disable_related_docs': true,
            'auto_size' : false,
            'height' : '100%'
          }, function(key, value){
            sd.addParam(key, value);
        });

        sd.addEventListener('iPaperReady', function(){
          EG.resizeFullHeight();
        });

        sd.write( 'scribd_doc_holder' );
        $scribd_doc_holder.show();
    },

    toggleFullRubric: function(force){
      //if there is no rubric associated with this assignment, then the edit rubric thing should never be shown.
      //the view should make sure that the edit rubric html is not even there but we also want to
      //make sure that pressing "r" wont make it appear either
      if (!jsonData.rubric_association){ return false; }

      if ($rubric_full.filter(":visible").length || force === "close") {
        $("#grading").height("auto").children().show();
        $rubric_full.fadeOut();
      }
      else {
        $rubric_full.fadeIn();
        rubricAssessment.populateRubric($rubric_full.find(".rubric"), getSelectedAssessment() );
        $("#grading").height($rubric_full.height()).children().hide();
      }
      this.resizeFullHeight();
    },

    handleFragementChange: function(){
      var hash;
      try {
        hash = JSON.parse(decodeURIComponent(document.location.hash.substr(1))); //get rid of the first charicter "#" of the hash
      } catch(e) {
        hash = {};
      }

      //if there is not a valid student_id in the location.hash then force it to be the first student in the class.
      if (typeof(hash.student_id) != "number" ||
          !$.grep(jsonData.studentsWithSubmissions, function(s){
            return hash.student_id == s.id;}).length) {
        hash.student_id = jsonData.studentsWithSubmissions[0].id;
      }

      EG.goToStudent(hash.student_id);
    },

    goToStudent: function(student_id){
      var student = $.grep(jsonData.studentsWithSubmissions, function(o){
  	    return o.id === student_id;
  	  })[0];

  	  var indexOfStudentInOptions = $selectmenu.find('option').index($selectmenu.find('option[value="' + student.id + '"]'));
  	  if (!(indexOfStudentInOptions >= 0)) {
  	    throw "student not found";
  	  }
  	  $selectmenu.selectmenu("value", indexOfStudentInOptions);
  	  //this is lame but I have to manually tell $selectmenu to fire its 'change' event if has changed.
  	  if (!this.currentStudent || (this.currentStudent.id != student.id)) {
  	    $selectmenu.change();
  	  }
    },

    currentIndex: function(){
      return $.inArray(this.currentStudent, jsonData.studentsWithSubmissions);
    },

    handleStudentChanged: function(){
      var id = parseInt( $selectmenu.val(), 10 );
      this.currentStudent = $.grep(jsonData.studentsWithSubmissions, function(o){
  	    return o.id === id;
  	  })[0];
  	  document.location.hash = "#" + encodeURIComponent(JSON.stringify({
  	    "student_id": this.currentStudent.id
  	  }));

  	  this.showGrade();
  	  this.toggleFullRubric("close");
  	  this.showDiscussion();
  	  this.showRubric();
  	  this.updateStatsInHeader();
      this.showSubmissionDetails();
    },

    handleSubmissionSelectionChange: function(){
      var currentSelectedIndex = ( 
            $submission_to_view.filter(":visible").length ? 
            Number($submission_to_view.filter(":visible").val()) : 
            (this.currentStudent.submission.currentSelectedIndex || 0)
          ),
          submission  = this.currentStudent.submission.submission_history[currentSelectedIndex].submission,
          dueAt       = jsonData.due_at && $.parseFromISO(jsonData.due_at),
          submittedAt = submission.submitted_at && $.parseFromISO(submission.submitted_at),
          gradedAt    = submission.graded_at && $.parseFromISO(submission.graded_at),
          scribdableAttachments = [],
          browserableAttachments = [];

      $single_submission_submitted_at.html(submittedAt && submittedAt.datetime_formatted);
      var turnitin = submission.turnitin_data && submission.turnitin_data['submission_' + submission.id];
      var turnitin_url = "#";
      if(turnitin) {
        turnitin_url = $.replaceTags($.replaceTags($("#assignment_submission_turnitin_url").attr('href'), 'user_id', submission.user_id), 'asset_string', 'submission_' + submission.id);
      }
      $grade_container.find(".turnitin_similarity_score")
        .css('display', (turnitin && turnitin.similarity_score != null) ? '' : 'none')
        .attr('href', turnitin_url)
        .attr('class', 'turnitin_similarity_score ' + ((turnitin && turnitin.state) || 'no') + '_score')
        .find(".similarity_score").text((turnitin && turnitin.similarity_score) || "--");
      
      //handle the files
      $submission_files_list.html("");
      $.each(submission.versioned_attachments, function(i,a){
        var attachment = a.attachment;
        if (attachment.scribd_doc && attachment.scribd_doc.created) {
          scribdableAttachments.push(attachment);
        }
        if (broswerableCssClasses.test(attachment.mime_class)) {
          browserableAttachments.push(attachment);
        }
        var turnitin = submission.turnitin_data && submission.turnitin_data['attachment_' + attachment.id];
        var turnitin_url = "#";
        if(turnitin) {
          turnitin_url = $.replaceTags($.replaceTags($("#assignment_submission_turnitin_url").attr('href'), 'user_id', submission.user_id), 'asset_string', 'attachment_' + attachment.id);
        }
        $submission_file_hidden.clone(true).fillTemplateData({
          data: {
            submissionId: submission.user_id,
            attachmentId: attachment.id,
            display_name: attachment.display_name,
            similarity_score: turnitin && turnitin.similarity_score
          },
          hrefValues: ['submissionId', 'attachmentId']
        }).appendTo($submission_files_list)
          .find('a.display_name')
            .addClass(attachment.mime_class)
            .data('attachment', attachment)
            .click(function(event){
              event.preventDefault();
              EG.loadAttachmentInline($(this).data('attachment'));
            })
          .end()
          .find('a.turnitin_similarity_score')
            .attr('href', turnitin_url)
            .attr('class', 'turnitin_similarity_score ' + ((turnitin && turnitin.state) || 'no') + '_score')
            .attr('target', '_blank')
            .css('display', (turnitin && turnitin.similarity_score != null) ? '' : 'none')
          .end()
          .find('a.submission-file-download')
            .bind('dragstart', function(event){
              // check that event dataTransfer exists
              event.originalEvent.dataTransfer &&
              // handle dragging out of the browser window only if it is supported.
              event.originalEvent.dataTransfer.setData('DownloadURL', attachment.content_type + ':' + attachment.filename + ':' + this.href);
            })
          .end()
          .show();
      });

      $submitted_files_plurality.html(submission.versioned_attachments.length > 1 ? "s" : "");
      $submission_files_container.showIf(submission.versioned_attachments.length);

      // load up a preview of one of the attachments if we can.
      // do it in this order:
      // show the first scridbable doc if there is one
      // then show the first image if there is one,
      // if not load the generic thing for the current submission (by not passing a value)
      this.loadAttachmentInline(scribdableAttachments[0] || browserableAttachments[0]);
      
      // if there is any submissions after this one, show a notice that they are not looking at the newest
      $submission_not_newest_notice.showIf($submission_to_view.filter(":visible").find(":selected").nextAll().length);

      // if the submission was after the due date, mark it as late
      this.resizeFullHeight();
      $submission_late_notice.showIf(dueAt && submittedAt && (submittedAt.minute_timestamp > dueAt.minute_timestamp) );
    },

    refreshSubmissionsToView: function(){
      var dueAt = jsonData.due_at && $.parseFromISO(jsonData.due_at);

      //if there are multiple submissions
      if (this.currentStudent.submission.submission_history && this.currentStudent.submission.submission_history.length > 1 ) {
        var innerHTML = "",
            submissionToSelect = this.currentStudent.submission.submission_history[this.currentStudent.submission.submission_history.length - 1].submission;

        $.each(this.currentStudent.submission.submission_history, function(i, s){
          s = s.submission;
          var submittedAt = s.submitted_at && $.parseFromISO(s.submitted_at),
              late        = dueAt && submittedAt && submittedAt.timestamp > dueAt.timestamp;
              
          innerHTML += "<option " + (late ? "class='late'" : "") + " value='" + i + "' " +
                        (s == submissionToSelect ? "selected='selected'" : "") + ">" +
                        (submittedAt && submittedAt.datetime_formatted || 'no submission time') +
                        (late ? " LATE" : "") +
                        (s.grade && s.grade_matches_current_submission ? " (grade: " + s.grade +")" : "") +
                       "</option>";
        });
        $submission_to_view.html(innerHTML);
        $multiple_submissions.show();
        $single_submission.hide();
      }
      else { //only submitted once
        $multiple_submissions.hide();
        $single_submission.show();
      }
    },
    
    showSubmissionDetails: function(){
      //if there is a submission
      if (this.currentStudent.submission && this.currentStudent.submission.submitted_at) {
        this.refreshSubmissionsToView();
        $submission_details.show();
        this.handleSubmissionSelectionChange();
      }
      else { //there's no submission
        this.loadAttachmentInline();
        $submission_details.hide();
      }
      this.resizeFullHeight();
    },

    updateStatsInHeader: function(){
      $x_of_x_students.html( $.ordinalize(EG.currentIndex() + 1) );

      var gradedStudents = $.grep(jsonData.studentsWithSubmissions, function(s){
        return (s.submission && s.submission.workflow_state === 'graded');
      });
      var scores = $.map(gradedStudents, function(s){
        return s.submission.score;
      });
      //scores shoud be an array that has all of the scores of the students that have submisisons

      if (scores.length) { //if there are some submissions that have been graded.
        $average_score_wrapper.show();
        function avg(arr) {
          var sum = 0;
          for (var i = 0, j = arr.length; i < j; i++) {
            sum += arr[i];
          }
          return sum / arr.length;
        }
        function roundWithPrecision(number, precision) {
        	precision = Math.abs(parseInt(precision, 10)) || 0;
        	var coefficient = Math.pow(10, precision);
        	return Math.round(number*coefficient)/coefficient;
        }
        var outOf = jsonData.points_possible ? ([" / ", jsonData.points_possible, " (", Math.round( 100 * (avg(scores) / jsonData.points_possible)), "%)"].join("")) : "";
        $average_score.html( [roundWithPrecision(avg(scores), 2) + outOf].join("") );
      }
      else { //there are no submissions that have been graded.
        $average_score_wrapper.hide();
      }
      $grded_so_far.html(scores.length);
    },

    loadAttachmentInline: function(attachment){
      $submissions_container.children().hide();
      if (!this.currentStudent.submission || !this.currentStudent.submission.submission_type) {
  	    $this_student_does_not_have_a_submission.show();
  	  }
  	  else {
        $iframe_holder.empty();
        $iframe_holder.find("iframe").remove();
  	    if (attachment && attachment.scribd_doc && attachment.scribd_doc.created && attachment.worflow_state != 'errored') { //if it's a scribd doc load it.
	        this.loadScribdDoc(attachment.scribd_doc.attributes);
	      }
	      else if (attachment && broswerableCssClasses.test(attachment.mime_class)) {
	        var src = unescape($submission_file_hidden.find('.display_name').attr('href'))
	                  .replace("{{submissionId}}", this.currentStudent.submission.user_id)
	                  .replace("{{attachmentId}}", attachment.id);
	        $iframe_holder.html('<iframe src="'+src+'" frameborder="0"></iframe>').show();
	      }
	      else {
	        //load in the iframe preview.  if we are viewing a past version of the file pass the version to preview in the url
	        $iframe_holder.html(
            '<iframe src="/courses/' + jsonData.context_id  +
            '/assignments/' + this.currentStudent.submission.assignment_id +
            '/submissions/' + this.currentStudent.submission.user_id +
            '?preview=true' + (
              this.currentStudent.submission &&
              !isNaN(this.currentStudent.submission.currentSelectedIndex ) ?
              '&version=' + this.currentStudent.submission.currentSelectedIndex :
              ''
            ) +'" frameborder="0"></iframe>')
            .show();
	      }
  	  }
    },

    showRubric: function(){
      //if this has some rubric_assessments
      if (jsonData.rubric_association) {
        rubricAssessment.assessment_user_id = this.currentStudent.id;

        var assessmentsByMe = $.grep(EG.currentStudent.rubric_assessments, function(n,i){
          return n.assessor_id === rubricAssessment.assessor_id;
        });
        var gradingAssessments = $.grep(EG.currentStudent.rubric_assessments, function(n,i){
          return n.assessment_type == 'grading';
        });

        $rubric_assessments_select.find("option").remove().end();
        $.each(this.currentStudent.rubric_assessments, function(){
          $rubric_assessments_select.append('<option value="' + this.id + '">' + this.assessor_name + '</option>');
        });

        // show a new option if there is not an assessment by me
        // or, if I can :manage_course, there is not an assessment already with assessment_type = 'grading'
        if( !assessmentsByMe.length || (rubricAssessment.assessment_type == 'grading' && !gradingAssessments.length) ) {
          $rubric_assessments_select.append('<option value="new">[New Assessment]</option>');
        }

        //select the assessment that meets these rules:
        // 1. the assessment by me
        // 2. the assessment with assessment_type = 'grading'
        var idToSelect = null;
        if (gradingAssessments.length) {
          idToSelect = gradingAssessments[0].id;
        }
        if (assessmentsByMe.length) {
          idToSelect = assessmentsByMe[0].id;
        }
        if (idToSelect) {
          $rubric_assessments_select.val(idToSelect);
        }

        // hide the select box if there is not >1 option
        $("#rubric_assessments_list").showIf($rubric_assessments_select.find("option").length > 1);
        $rubric_assessments_select.change();
      }
    },

    showDiscussion: function(){
      $comments.html("");
      if (this.currentStudent.submission && this.currentStudent.submission.submission_comments) {
        $.each(this.currentStudent.submission.submission_comments, function(i, comment){
          // Serialization seems to have changed... not sure if it's changed everywhere, though...
          if(comment.submission_comment) { comment = comment.submission_comment; }
          comment.posted_at = $.parseFromISO(comment.created_at).datetime_formatted;

          // if(comment.anonymous) { comment.author_name = "Anonymous"; }
          var $comment = $comment_blank.clone(true).fillTemplateData({ data: comment });
          $comment.find('span.comment').html($.htmlEscape(comment.comment).replace(/\n/g, "<br />"));
          // this is really poorly decoupled but over in speed_grader.html.erb these rubricAssessment. variables are set.
          // what this is saying is: if I am able to grade this assignment (I am administrator in the course) or if I wrote this comment...
          var commentIsDeleteableByMe = rubricAssessment.assessment_type === "grading" || 
                                        rubricAssessment.assessor_id === comment.author_id;

          $comment.find(".delete_comment_link").click(function(event) {
            $(this).parents(".comment").confirmDelete({
              url: "/submission_comments/" + comment.id,
              message: "Are you sure you want to delete this comment?",
              success: function(data) {
                $(this).slideUp(function() {
                  $(this).remove();
                });
              }
            });
          }).showIf(commentIsDeleteableByMe);
          
          if (comment.media_comment_type && comment.media_comment_id) {
            $comment.find(".play_comment_link").show();
          }
          $.each((comment.cached_attachments || comment.attachments), function(){
            var attachment = this.attachment || this;
            attachment.comment_id = comment.id;
            attachment.submitter_id = EG.currentStudent.id;
            $comment.find(".comment_attachments").append($comment_attachment_blank.clone(true).fillTemplateData({
              data: attachment,
              hrefValues: ['comment_id', 'id', 'submitter_id']
            }).show().find("a").addClass(attachment.mime_class));
          });
          $comments.append($comment.show());
          $comments.find(".play_comment_link").mediaCommentThumbnail('normal');
        });
      }
      $comments.scrollTop(9999999);  //the scrollTop part forces it to scroll down to the bottom so it shows the most recent comment.
    },

    revertFromFormSubmit: function() {
        EG.showDiscussion();
        EG.resizeFullHeight();
        $add_a_comment_textarea.val("");
        // HACK, HACK, HACK
        // this is really weird but in webkit if you do $add_a_comment_textarea.val("").trigger('keyup') it will not let you
        // type it the textarea after you do that.  but I put it in a setTimeout it works.  so this is a HACK for webkit,
        // but it still works in all other browsers.
        setTimeout(function(){ $add_a_comment_textarea.trigger('keyup'); }, 0);

        $add_a_comment.find(":input").attr("disabled", false);
        $add_a_comment_submit_button.text("Submit Comment");
    },
    
    handleCommentFormSubmit: function(){
      if (
        !$.trim($add_a_comment_textarea.val()).length &&
        !$("#media_media_recording").data('comment_id') &&
        !$add_a_comment.find("input[type='file']:visible").length
        ) {
          // that means that they did not type a comment, attach a file or record any media. so dont do anything.
        return false;
      }
      var url = assignmentUrl + "/submissions/" + EG.currentStudent.id;
      var method = "PUT";
      var formData = {
        'submission[assignment_id]': jsonData.id,
        'submission[user_id]': EG.currentStudent.id,
        'submission[group_comment]': ($("#submission_group_comment").attr('checked') ? "1" : "0"),
        'submission[comment]': $add_a_comment_textarea.val()
      };
      if ($("#media_media_recording").data('comment_id')) {
        $.extend(formData, {
          'submission[media_comment_type]': $("#media_media_recording").data('comment_type'),
          'submission[media_comment_id]': $("#media_media_recording").data('comment_id')
        });
      }

      function formSuccess(submissions) {
        $.each(submissions, function(){
          EG.setOrUpdateSubmission(this.submission);
        });
        EG.revertFromFormSubmit();
      }
      if($add_a_comment.find("input[type='file']:visible").length) {
        $.ajaxJSONFiles(url + ".text", method, formData, $add_a_comment.find("input[type='file']:visible"), formSuccess);
      } else {
        $.ajaxJSON(url, method, formData, formSuccess);
      }

      $("#comment_attachments").empty();
      $add_a_comment.find(":input").attr("disabled", true);
      $add_a_comment_submit_button.text("Submitting...");
      hideMediaRecorderContainer();
    },
    
    setOrUpdateSubmission: function(submission){
      // find the student this submission belongs to and update their submission with this new one, if they dont have a submission, set this as their submission.
      var student =  $.grep(jsonData.studentsWithSubmissions, function(s){ return s.id === submission.user_id; })[0];
      student.submission = student.submission || {};
      $.extend(true, student.submission, submission);
      return student;
    },

    handleGradeSubmit: function(){
      var url    = $(".update_submission_grade_url").attr('href'),
          method = $(".update_submission_grade_url").attr('title'),
          formData = {
            'submission[assignment_id]': jsonData.id,
            'submission[user_id]':       EG.currentStudent.id,
            'submission[grade]':         $grade.val()
          };

      $.ajaxJSON(url, method, formData, function(submissions) {
        $.each(submissions, function(){
          EG.setOrUpdateSubmission(this.submission);
        });
        EG.refreshSubmissionsToView();
        $submission_to_view.change();
        EG.showGrade();
      });
    },
    
    showGrade: function(){
      $grade.val( typeof EG.currentStudent.submission != "undefined" && 
                  EG.currentStudent.submission.grade !== null ?
                  EG.currentStudent.submission.grade : "")
            .attr('disabled', typeof EG.currentStudent.submission != "undefined" && 
                              EG.currentStudent.submission.submission_type === 'online_quiz');

      $('#submit_same_score').hide();
      if (typeof EG.currentStudent.submission != "undefined" &&
          EG.currentStudent.submission.score !== null) {
        $score.text(EG.currentStudent.submission.score);
        if (!EG.currentStudent.submission.grade_matches_current_submission) {
          $('#submit_same_score').show();
        }
      } else {
        $score.text("");
      }

      EG.updateStatsInHeader();

      // go through all the students and change the class of for each person in the selectmenu to reflect it has / has not been graded.
      // for the current student, you have to do it for both the li as well as the one that shows which was selected (AKA $selectmenu.data('selectmenu').newelement ).
      // this might be the wrong spot for this, it could be refactored into its own method and you could tell pass only certain students that you want to update
      // (ie the current student or all of the students in the group that just got graded)
      $.each(jsonData.studentsWithSubmissions, function(index, val) {
        var $query = $selectmenu.data('selectmenu').list.find("li:eq("+ index +")"),
            className = classNameBasedOnStudent(this),
            submissionStates = 'not_graded not_submitted graded resubmitted';
        
        if (this == EG.currentStudent) {
          $query = $query.add($selectmenu.data('selectmenu').newelement);
        }
        $query
          .removeClass(submissionStates)
          .addClass(className.raw)
          .find(".ui-selectmenu-item-footer")
            .text(className.formatted);

        // this is because selectmenu.js uses .data('optionClasses' on the li to keep track
        // of what class to put on the selected option ( aka: $selectmenu.data('selectmenu').newelement ) 
        // when this li is selected.  so even though we set the class of the li and the 
        // $selectmenu.data('selectmenu').newelement when it is graded, we need to also set the data()
        // so that if you skip back to this student it doesnt show the old checkbox status.
        $.each(submissionStates.split(' '), function(){
          $query.data('optionClasses', $query.data('optionClasses').replace(this, ''));
        });
      });

    },

    initComments: function(){
      $add_a_comment_submit_button.click(function(event) {
        event.preventDefault();
        EG.handleCommentFormSubmit();
      });
      $add_attachment.click(function(event) {
        event.preventDefault();
        var $attachment = $comment_attachment_input_blank.clone(true);
        $attachment.find("input").attr('name', 'attachments[' + fileIndex + '][uploaded_data]');
        fileIndex++;
        $("#comment_attachments").append($attachment.show());
        EG.resizeFullHeight();
      });
      $comment_attachment_input_blank.find("a").click(function(event) {
        event.preventDefault();
        $(this).parents(".comment_attachment_input").remove();
        EG.resizeFullHeight();
      });
      $right_side.delegate(".play_comment_link", 'click', function() {
        var comment_id = $(this).parents(".comment").getTemplateData({textValues: ['media_comment_id']}).media_comment_id;
        if(comment_id) {
          $(this).parents(".comment").find(".media_comment_content").show().mediaComment('show', comment_id, 'audio');
        }
        return false; // so that it doesn't hit the $("a.instructure_inline_media_comment").live('click' event handler
      });
    }
  };

  //run the stuff that just attaches event handlers and dom stuff, but does not need the jsonData
  $(EG.domReady);

})(jQuery, INST, scribd, rubricAssessment);
