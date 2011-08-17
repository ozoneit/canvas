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

$(document).ready(function() {
  var $add_section_form = $("#add_section_form"),
      $edit_section_form = $("#edit_section_form"),
      $course_form = $("#course_form"),
      $hashtag_form = $(".hashtag_form"),
      $course_hashtag = $("#course_hashtag"),
      $enroll_users_form = $("#enroll_users_form"),
      $enrollment_dialog = $("#enrollment_dialog");
      
  $("#course_details_tabs").tabs({cookie: {}}).show();
      
  $add_section_form.formSubmit({
    required: ['course_section[name]'],
    beforeSubmit: function(data) {
      $add_section_form.find("button").attr('disabled', true).text("Adding Section...");
    },
    success: function(data) {
      var section = data.course_section,
          $section = $(".section_blank:first").clone(true).attr('class', 'section'),
          $option = $("<option/>");
          
      $add_section_form.find("button").attr('disabled', false).text("Add Section");
      $section.fillTemplateData({
        data: section,
        hrefValues: ['id']
      });
      $("#course_section_id_holder").show();
      $option.val(section.id).text(section.name).addClass('option_for_section_' + section.id);
      $("#sections .section_blank").before($section);
      $section.slideDown();
      $("#course_section_name").val();
    },
    error: function(data) {
      $add_section_form
        .formErrors(data)
        .find("button").attr('disabled', false).text("Add Section Failed, Please Try Again");
    }
  });
  $(".cant_delete_section_link").click(function(event) {
    alert($(this).attr('title'));
    return false;
  });
  $edit_section_form.formSubmit({
    beforeSubmit: function(data) {
      $edit_section_form.hide();
      var $section = $edit_section_form.parents(".section");
      $section.find(".name").text(data['course_section[name]']).show();
      $section.loadingImage({image_size: "small"});
      return $section;
    },
    success: function(data, $section) {
      var section = data.course_section;
      $section.loadingImage('remove');
      $(".option_for_section_" + section.id).text(section.name);
    },
    error: function(data, $section) {
      $section.loadingImage('remove').find(".edit_section_link").click();
      $edit_section_form.formErrors(data);
    }
  })
  .find(":text")
    .bind('blur', function() {
      $edit_section_form.submit();
    })
    .keycodes('return esc', function(event) {
      if(event.keyString == 'return') {
        $edit_section_form.submit();
      } else {
        $(this).parents(".section").find(".name").show();
        $("body").append($edit_section_form.hide());
      }
    });
  $(".edit_section_link").click(function() {
    var $this = $(this),
        $section = $this.parents(".section"),
        data = $section.getTemplateData({textValues: ['name']});
    $edit_section_form.fillFormData(data, {object_name: "course_section"});
    $section.find(".name").hide().after($edit_section_form.show());
    $edit_section_form.attr('action', $this.attr('href'));
    $edit_section_form.find(":text:first").focus().select();
    return false;
  });
  $(".delete_section_link").click(function() {
    $(this).parents(".section").confirmDelete({
      url: $(this).attr('href'),
      message: "Are you sure you want to delete this section?",
      success: function(data) {
        $(this).slideUp(function() {
          $(this).remove();
        });
      }
    });
    return false;
  });
  $("#nav_form").submit(function(){
    tab_id_regex = /(\d+)$/;
    function tab_id_from_el(el) {
      var tab_id_str = $(el).attr("id");
      if (tab_id_str) {
        var comps = tab_id_str.split('_');
        if (comps.length > 0) {
          tab_id = parseInt(comps.pop(), 10);
          return tab_id;
        }
      }
      return null;
    }
    
    var tabs = [];
    $("#nav_enabled_list li").each(function() {
      var tab_id = tab_id_from_el(this);
      if (tab_id !== null) { tabs.push({ id: tab_id }); }
    });
    $("#nav_disabled_list li").each(function() {
      var tab_id = tab_id_from_el(this);
      if (tab_id !== null) { tabs.push({ id: tab_id, hidden: true }); }
    });
    
    $("#tabs_json").val(JSON.stringify(tabs));
    return true;
  });
  
  $(".edit_nav_link").click(function(event) {
    event.preventDefault();
    $("#nav_form").dialog('close').dialog({
      modal: true,
      resizable: false,
      width: 400
    }).dialog('open');
  });
  
  $("#nav_enabled_list, #nav_disabled_list").sortable({
    items: 'li.enabled',
    connectWith: '.connectedSortable',
    axis: 'y'
  }).disableSelection();

  
  $(".hashtag_dialog_link").click(function(event) {
    event.preventDefault();
    $("#hashtag_dialog").dialog('close').dialog({
      autoOpen: false,
      title: "What's a Hashtag?",
      width: 500
    }).dialog('open');
  });
  $(".close_dialog_button").click(function() {
    $("#hashtag_dialog").dialog('close');
  });
  $("#course_hashtag").bind('blur change keyup', function() {
    var val = $(this).val() || "";
    val = val.replace(/(\s)+/g, "_").replace(/#/, "");
    $("#hashtag_options").showIf(val && val !== "");
    $(this).val(val);
  });
  $(document).fragmentChange(function(event, hash) {
    function handleFragmentType(val){
      $("#tab-users-link").click();
      $(".add_users_link:visible").click();
      $("#enroll_users_form select[name='enrollment_type']").val(val);
    }
    if(hash == "#add_students") {
      handleFragmentType("StudentEnrollment");
    } else if(hash == "#add_tas") {
      handleFragmentType("TaEnrollment");
    } else if(hash == "#add_teacher") {
      handleFragmentType("TeacherEnrollment");
    }
  });
  $(".edit_course_link").click(function(event) {
    var $course_account_id_lookup = $("#course_account_id_lookup");
    event.preventDefault();
    $("#course_form").addClass('editing').find(":text:first").focus().select();
    if($course_account_id_lookup.length && !$course_account_id_lookup.data('autocomplete')) {
      $course_account_id_lookup.data('autocomplete', $course_account_id_lookup.autocomplete({
        serviceUrl: $("#course_account_id_url").attr('href'),
        onSelect: function(value, data){
          $("#course_account_id").val(data.id);
        }
      }));
    }
    $hashtag_form.showIf($course_hashtag.text().length > 0);
    $course_hashtag.triggerHandler('blur');
  });
  $(".move_course_link").click(function(event) {
    event.preventDefault();
    $("#move_course_dialog").dialog('close').dialog({
      autoOpen: false,
      title: "Move Course",
      width: 500
    }).dialog('open');
  });
  $("#move_course_dialog").delegate('.cancel_button', 'click', function() {
    $("#move_course_dialog").dialog('close');
  });
  $course_form.formSubmit({
    processData: function(data) {
      data['course[hashtag]'] = (data['course[hashtag]'] || "").replace(/\s/g, "_").replace(/#/g, "");
      if(data['course[start_at]']) {
        data['course[start_at]'] += " 12:00am";
      }
      if(data['course[conclude_at]']) {
        data['course[conclude_at]'] += " 11:55pm";
      }
      return data;
    },
    beforeSubmit: function(data) {
      $(this).loadingImage().removeClass('editing');
      $(this).find(".readable_license,.account_name,.term_name").text("...");
      $(this).find(".quota").text(data['course[storage_quota]']);
      $(".course_form_more_options").hide();
    },
    success: function(data) {
      $(this).loadingImage('remove');
      var course = data.course;
      course.start_at = $.parseFromISO(course.start_at).datetime_formatted;
      course.conclude_at = $.parseFromISO(course.conclude_at).datetime_formatted;
      course.is_public = course.is_public ? 'Public' : 'Private';
      course.indexed = course.indexed ? "Included in public course index" : "";
      course.restrict_dates = course.restrict_enrollments_to_course_dates ? "Users can only access the course between these dates" : "These dates will not affect course availability";
      $("#course_form .public_options").showIf(course.is_public);
      $("#course_form .self_enrollment_message").css('display', course.self_enrollment ? '' : 'none');
      $("#course_form").fillTemplateData({data: course});
      $(".hashtag_form").showIf($("#course_hashtag").text().length > 0);
    }
  })
  .find(".cancel_button")
    .click(function() {
      $course_form.removeClass('editing');
      $hashtag_form.showIf($course_hashtag.text().length > 0);
      $(".course_form_more_options").hide();
    }).end()
  .find(":text:not(.date_entry)").keycodes('esc', function() {
    $course_form.find(".cancel_button:first").click();
  });
  $enroll_users_form.hide();
  $(".add_users_link").click(function(event) {
    $(this).hide();
    event.preventDefault();
    $("#enroll_users_form").show();
    $("html,body").scrollTo($enroll_users_form);
    $enroll_users_form.find("textarea").focus().select();
  });
  $(".associate_user_link").click(function(event) {
    event.preventDefault();
    var $user = $(this).parents(".user");
    var data = $user.getTemplateData({textValues: ['name', 'associated_user_id', 'id']});
    link_enrollment.choose(data.name, data.id, data.associated_user_id, function(enrollment) {
      if(enrollment) {
        var user_name = enrollment.associated_user_name;
        $("#enrollment_" + enrollment.id)
          .find(".associated_user.associated").showIf(enrollment.associated_user_id).end()
          .find(".associated_user.unassociated").showIf(!enrollment.associated_user_id).end()
          .fillTemplateData({data: enrollment});
      }
    });
  });
  $(".course_info").attr('title', 'Click to Edit').click(function() {
    $(".edit_course_link:first").click();
    var $obj = $(this).parents("td").find(".course_form");
    if($obj.length) {
      $obj.focus().select();
    }
  });
  $(".course_form_more_options_link").click(function(event) {
    event.preventDefault();
    $(".course_form_more_options").slideToggle();
  });
  $(".user_list").delegate('.user', 'mouseover', function(event) {
    var $this = $(this),
        title = $this.attr('title'),
        pending_message = "This user has not yet accepted their invitation.  Click to re-send invitation.";
    
    if(title != pending_message) {
      $this.data('real_title', title);
    }
    if($this.hasClass('pending')) {
      $this.attr('title', pending_message).css('cursor', 'pointer');
    } else {
      $this.attr('title', $(this).data('real_title') || "User").css('cursor', '');
    }
  });
  $enrollment_dialog.find(".cancel_button").click(function() {
    $enrollment_dialog.dialog('close');
  });
  
  $(".user_list").delegate('.user_information_link', 'click', function(event) {
    var $this = $(this),
        $user = $this.closest('.user'),
        pending = $user.hasClass('pending'),
        data = $user.getTemplateData({textValues: ['name', 'invitation_sent_at']}),
        admin = $user.parents(".teacher_enrollments,.ta_enrollments").length > 0;
    
    data.re_send_invitation_link = "Re-Send Invitation";
    $enrollment_dialog
      .data('user', $user)
      .find(".re_send_invitation_link")
        .attr('href', $user.find(".re_send_confirmation_url").attr('href')).end()
      .find(".student_enrollment_re_send").showIf(pending && !admin).end()
      .find(".admin_enrollment_re_send").showIf(pending && admin).end()
      .find(".accepted_enrollment_re_send").showIf(!pending).end()
      .find(".invitation_sent_at").showIf(pending).end()
      .fillTemplateData({data: data})
      .dialog('close')
      .dialog({ autoOpen: false, title: "Enrollment Details" })
      .dialog('open');
    return false;
  });
  
  $enrollment_dialog.find(".re_send_invitation_link").click(function(event) {
    event.preventDefault();
    var $link = $(this);
    $link.text("Re-Sending Invitation...");
    var url = $link.attr('href');
    $.ajaxJSON(url, 'POST', {}, function(data) {
      $enrollment_dialog.fillTemplateData({data: {invitation_sent_at: "Just Now"}});
      $link.text("Invitation Sent!");
      var $user = $enrollment_dialog.data('user');
      if($user) {
        $user.fillTemplateData({data: {invitation_sent_at: "Just Now"}});
      }
    }, function(data) {
      $link.text("Invitation Failed.  Please try again.");
    });
  });
  $(".date_entry").date_field();
  
  $().data('current_default_wiki_editing_roles', $("#course_default_wiki_editing_roles").val());
  $("#course_default_wiki_editing_roles").change(function() {
    var $this = $(this);
    $(".changed_default_wiki_editing_roles").showIf($this.val() != $().data('current_default_wiki_editing_roles'));
    $(".default_wiki_editing_roles_change").text($this.find(":selected").text());
  });
  
  $(".re_send_invitations_link").click(function(event) {
    event.preventDefault();
    var $button = $(this),
        oldText = "Re-Send All Unaccepted Invitations";
        
    $button.text("Re-Sending Unaccepted Invitations...").attr('disabled', true);
    $.ajaxJSON($button.attr('href'), 'POST', {}, function(data) {
      $button.text("Re-Sent All Unaccepted Invitations!").attr('disabled', false);
      $(".user_list .user.pending").each(function() {
        var $user = $(this);
        $user.fillTemplateData({data: {invitation_sent_at: "Just Now"}});
      });
      setTimeout(function() {
        $button.text(oldText);
      }, 2500);
    }, function() {
      $button.text("Send Failed, Please Try Again").attr('disabled', false);
    });
  });
  $("#enrollment_type").change(function() {
    $(".teacherless_invite_message").showIf($(this).find(":selected").hasClass('teacherless_invite'));
  });
  $(".is_public_checkbox").change(function() {
    $(".public_options").showIf($(this).attr('checked'));
  }).change();  
  
  $(".self_enrollment_checkbox").change(function() {
    $(".open_enrollment_holder").showIf($(this).attr('checked'));
  }).change();
  $.scrollSidebar();
});
