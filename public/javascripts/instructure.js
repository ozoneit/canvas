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

jQuery(function($) {
  
  // handle all of the click events that were triggered before the dom was ready (and thus weren't handled by jquery listeners)
  if (window._earlyClick) {
    
    // unset the onclick handler we were using to capture the events
    document.removeEventListener ?
      document.removeEventListener('click', _earlyClick, false) :
      document.detachEvent('onclick', _earlyClick);
      
    if (_earlyClick.clicks) {
      // wait to fire the "click" events till after all of the event hanlders loaded at dom ready are initialized
      setTimeout(function(){
        $.each($.uniq(_earlyClick.clicks), function() {
          // cant use .triggerHandler because it will not bubble, 
          // but we do want to preventDefault, so this is what we have to do
          var event = $.Event('click');
          event.preventDefault();
          $(this).trigger(event);
        });
      }, 1);
    }
  }

  ///////////// START layout related stuff
  // make sure that #main is at least as big as the tallest of #right_side, #content, and #left_side and ALWAYS at least 500px tall
  $('#main:not(.already_sized)').css({"minHeight" : Math.max($("#left_side").height(), parseInt(($('#main').css('minHeight') || "").replace('px', ''), 10))});
  
  var $menu_items = $(".menu-item"),
      menuItemHoverTimeoutId;
      
  function clearMenuHovers(){
    window.clearTimeout(menuItemHoverTimeoutId);
    $menu_items.removeClass("hover hover-pending");
  }
  
  function unhoverMenuItem(){
    $menu_items.filter(".hover-pending").removeClass('hover-pending');
    menuItemHoverTimeoutId = window.setTimeout(clearMenuHovers, 400);
    return false;
  }
  
  function hoverMenuItem(event){
    var hadClass = $menu_items.filter(".hover").length > 0;
    clearMenuHovers();
    var $elem = $(this);
    $elem.addClass('hover-pending');
    if(hadClass) { $elem.addClass('hover'); }
    setTimeout(function() {
      if($elem.hasClass('hover-pending')) {
        $elem.addClass("hover");
      }
    }, 300);
    return false;  
  }
  
  $menu_items.bind('mouseenter focusin' , hoverMenuItem ).bind('mouseleave focusout', unhoverMenuItem);

  // ie7 needs some help forcing the columns to be as wide as (width_of_one_column * #_of_columns_in_this_dropdown)
  if (INST.browser.ie7) {
    $(".menu-item-drop")
      .width(function(){
        var $columns = $(this).find(".menu-item-drop-column");
        return $columns.length * $columns.css('width').replace('px', '');
      });  
  }
  
  // this stuff is for the ipad, it needs a little help getting the drop menus to show up
  $menu_items.bind('touchstart', function(){
    // if we are not in an alredy hovering drop-down, drop it down, otherwise do nothing 
    // (so that if a link is clicked in one of the li's it gets followed).
    if(!$(this).hasClass('hover')){
      return hoverMenuItem.call(this, event);
    }
  });
  // If I touch anywhere on the screen besides inside a dropdown, make the dropdowns go away.
  $(document).bind('touchstart', function(event){
    if (!$(event.target).closest(".menu-item").length) {
      unhoverMenuItem();
    }
  });

  
  
  // this next block of code adds the ellipsis on the breadcrumb if it overflows one line
  var $breadcrumbs = $("#breadcrumbs"),
      $breadcrumbEllipsis,
      addedEllipsisClass = false;
  function resizeBreadcrumb(){
    var maxWidth = 500,
        // we want to make sure that the breadcrumb doesnt wrap multiple lines, the way we are going to check if it is one line
        // is by grabbing the first (which should be the home crumb) and checking to see how high it is, the * 1.5 part is 
        // just in case to ever handle any padding or margin.
        hightOfOneBreadcrumb = $breadcrumbs.find('li:visible:first').height() * 1.5;  
    $breadcrumbEllipsis = $breadcrumbEllipsis || $breadcrumbs.find('.ellipsible');
    $breadcrumbEllipsis.css('maxWidth', "");
    $breadcrumbEllipsis.ifExists(function(){
      for (var i=0; $breadcrumbs.height() > hightOfOneBreadcrumb && i < 20; i++) { //the i here is just to make sure we don't get into an ifinite loop somehow
        if (!addedEllipsisClass) {
          addedEllipsisClass = true;
          $breadcrumbEllipsis.addClass('ellipsis');
        }
        $breadcrumbEllipsis.css('maxWidth', (maxWidth -= 20));
      }
    });
  }
  resizeBreadcrumb(); //force it to run once right now
  $(window).resize(resizeBreadcrumb);
  // end breadcrumb ellipsis

  
  //////////////// END layout related stuff
  
  $("#ajax_authenticity_token").ifExists(function(){
    if(this.text()) {
      $("input[name='authenticity_token']").val(this.text());
    }
  });
  
  
  $(document).keycodes("shift+/", function(event) {
    $("#keyboard_navigation").dialog('close').dialog({
      title: "Keyboard Shortcuts",
      width: 400,
      height: "auto",
      autoOpen: false
    }).dialog('open');
  });
  
  $("#switched_role_type").ifExists(function(){
    var context_class = $(this).attr('class');
    var $img = $("<img/>");
    $img.attr('src', '/images/warning.png')
      .attr('title', "You have switched roles temporarily for this course, and are now viewing the course as a " + $(this).text().toLowerCase() + ".  You can restore your role and permissions from the course home page.")
      .css({
        paddingRight: 2,
        width: 12,
        height: 12
      });
    $("#crumb_" + context_class).find("a").prepend($img);
  });

  $("a.show_quoted_text_link").live('click', function(event) {
    var $text = $(this).parents(".quoted_text_holder").children(".quoted_text");
    if($text.length > 0) {
      event.preventDefault();
      $text.show();
      $(this).hide();
    }
  });
  
  $(".custom_search_results_link").click(function(event) {
    event.preventDefault();
    var $dialog = $("#custom_search_results_dialog");
    $dialog.dialog('close').dialog({
      autoOpen: false,
      title: "Search for Open Resources",
      width: 600,
      height: 400
    }).dialog('open');
    var control = $dialog.data('searchControl');
    if(control) {
      control.execute($("title").text());
    }
  });
  
  $("a.instructure_inline_media_comment").live('click', function(event) {
    event.preventDefault();
    if(INST.kalturaSettings) {
      var $link = $(this),
          $div = $("<span><span></span></span>"),
          mediaType = 'video',
          id = $link.find(".media_comment_id:first").text();
      $div.css('display', 'block');
      
      if(!id && $link.attr('id') && $link.attr('id').match(/^media_comment_/)) {
        id = $link.attr('id').substring(14);
      }
      $link.after($div);
      $link.hide(); //remove();
      if($(this).hasClass('audio_playback') || $(this).hasClass('audio_comment') || $(this).hasClass('instructure_audio_link')) { mediaType = 'audio'; }
      $div.children("span").mediaComment('show_inline', id, mediaType, $link.attr('href'));
      $div.append("<br/><a href='#' style='font-size: 0.8em;' class='hide_flash_embed_link'>Minimize Embedded Content</a>");
      $div.find(".hide_flash_embed_link").click(function(event) {
        event.preventDefault();
        $div.remove();
        $link.show();
        $.trackEvent('hide_embedded_content', 'hide_media');
      });
      $.trackEvent('show_embedded_content', 'show_media');
    } else {
      alert("Kaltura has been disabled for this Canvas site");
    }
  });
  
  $("a.equella_content_link").live('click', function(event) {
    event.preventDefault();
    var $dialog = $("#equella_preview_dialog");
    if( !$dialog.length ) {
      $dialog = $("<div/>");
      $dialog.attr('id', 'equella_preview_dialog').hide();
      $dialog.html("<h2/><iframe style='background: url(/images/ajax-loader-medium-444.gif) no-repeat left top; width: 800px; height: 350px; border: 0;' src='about:blank' borderstyle='0'/><div style='text-align: right;'><a href='#' class='original_link external external_link' target='_blank'>view the content in a new window</a>");
      $dialog.find("h2").text($(this).attr('title') || $(this).text() || "Equella Content Preview");
      var $iframe = $dialog.find("iframe");
      setTimeout(function() {
        $iframe.css('background', '#fff');
      }, 2500);
      $("body").append($dialog);
      $dialog.dialog({
        autoOpen: false,
        width: 'auto',
        resizable: false,
        title: "Equella Content Preview",
        close: function() {
          $dialog.find("iframe").attr('src', 'about:blank');
        }
      });
    }
    $dialog.find(".original_link").attr('href', $(this).attr('href'));
    $dialog.dialog('close').dialog('open');
    $dialog.find("iframe").attr('src', $(this).attr('href'));
  });

  function enhanceUserContent() {
    var $content = $("#content");
    $(".user_content:not(.enhanced):visible").addClass('unenhanced');
    $(".user_content.unenhanced:visible")
      .each(function() {
        var $this = $(this);
        $this.find("img").css('maxWidth', Math.min($content.width(), $this.width()));
        $this.data('unenhanced_content_html', $this.html());
      })
      .find("a:not(.not_external, .external):external").each(function(){
        $(this)
          .not(":has(img)")
          .addClass('external')
          .html('<span>' + $(this).html() + '</span>')
          .attr('target', '_blank')
          .append('<span class="ui-icon ui-icon-extlink ui-icon-inline" title="Links to an external site."/>');
      }).end()
      .find("a.instructure_file_link").each(function() {  
        var $link = $(this),
            $span = $("<span class='instructure_file_link_holder link_holder'/>"); 
        $link.removeClass('instructure_file_link').before($span).appendTo($span);
        if($link.attr('target') != '_blank') {
          $span.append("<a href='" + $link.attr('href') + "' target='_blank' title='View in a new window' style='padding-left: 5px;'><img src='/images/popout.png'/></a>");
        }
      });
    if(INST && INST.filePreviewsEnabled) {
      $("a.instructure_scribd_file:not(.inline_disabled)").each(function() {
        var $link = $(this);
        if($.trim($link.text())) {
          var $span = $("<span class='instructure_scribd_file_holder link_holder'/>"),
              $scribd_link = $("<a class='scribd_file_preview_link' href='" + $link.attr('href') + "' title='Preview the document' style='padding-left: 5px;'><img src='/images/preview.png'/></a>");
          $link.removeClass('instructure_scribd_file').before($span).appendTo($span);
          $span.append($scribd_link);
          if($link.hasClass('auto_open')) {
            $scribd_link.click();
          }
        }
      });
    }
    
    $(".user_content.unenhanced a")
      .find("img.media_comment_thumbnail").each(function() {
        $(this).closest("a").addClass('instructure_inline_media_comment');
      }).end()
      .filter(".instructure_inline_media_comment").removeClass('no-underline').mediaCommentThumbnail('normal').end()
      .filter(".instructure_video_link, .instructure_audio_link").mediaCommentThumbnail('normal', true).end()
      .not(".youtubed").each(function() {
        var $link = $(this),
            href = $link.attr('href'),
            id = $.youTubeID(href || "");
        if($link.hasClass('inline_disabled')) {
        } else if(id) {
          var $after = $('<a href="'+ href +'" class="youtubed"><img src="/images/play_overlay.png" class="media_comment_thumbnail" style="background-image: url(http://img.youtube.com/vi/' + id + '/2.jpg)"/></a>')
            .click(function(event) {
              event.preventDefault();
              var $video = $("<span class='youtube_holder' style='display: block;'><object width='425' height='344'><param name='wmode' value='opaque'></param><param name='movie' value='http://www.youtube.com/v/" + id + "&autoplay=1&hl=en_US&fs=1&'></param><param name='allowFullScreen' value='true'></param><param name='allowscriptaccess' value='always'></param><embed src='http://www.youtube.com/v/" + id + "&autoplay=1&hl=en_US&fs=1&' type='application/x-shockwave-flash' allowscriptaccess='always' allowfullscreen='true' width='425' height='344' wmode='opaque'></embed></object><br/><a href='#' style='font-size: 0.8em;' class='hide_youtube_embed_link'>Minimize Video</a></span>");
              $video.find(".hide_youtube_embed_link").click(function(event) {
                event.preventDefault();
                $video.remove();
                $after.show();
                $.trackEvent('hide_embedded_content', 'hide_you_tube');
              });
              $(this).after($video).hide();
            });
          $.trackEvent('show_embedded_content', 'show_you_tube');
          $link
            .addClass('youtubed')
            .after($after);
        }
      });
    $(".user_content.unenhanced").removeClass('unenhanced').addClass('enhanced');
  };
  if(INST && INST.filePreviewsEnabled) {
    $("a.scribd_file_preview_link").live('click', function(event) {
      event.preventDefault();
      $(this).loadingImage({image_size: 'small'});
      var $link = $(this);
      $.ajaxJSON($(this).attr('href').replace(/\/download.*/, ""), 'GET', {}, function(data) {
        $link.loadingImage('remove');
        var attachment = data.attachment;
        if(attachment && attachment.scribd_doc && attachment.scribd_doc.attributes) {
          var id = $.uniqueId("scribd_preview_");
          var $div = $("<span id='" + id + "'/>");
          $link.parents(".link_holder:last").after($div);
          var sd = scribd.Document.getDoc( attachment.scribd_doc.attributes.doc_id, attachment.scribd_doc.attributes.access_key );
          $.each({
              'jsapi_version': 1,
              'disable_related_docs': true,
              'auto_size' : false,
              'height' : '400px'
            }, function(key, value){
              sd.addParam(key, value);
          });

          sd.write( id );
          $div.append("<br/><a href='#' style='font-size: 0.8em;' class='hide_file_preview_link'>Minimize File Preview</a>");
          $div.find(".hide_file_preview_link").click(function(event) {
            event.preventDefault();
            $link.show();
            $div.remove();
            $.trackEvent('hide_embedded_content', 'hide_file_preview');
          });
          $.trackEvent('show_embedded_content', 'show_file_preview');
        }
        $link.hide();
      }, function() {
        $link.loadingImage('remove');
        $link.hide();
      });
    });
  } else {
    $("a.scribd_file_preview_link").live('click', function(event) {
      event.preventDefault();
      alert('File previews have been disabled for this Canvas site');
    });
  }
  $(document).bind('user_content_change', enhanceUserContent);
  setInterval(enhanceUserContent, 15000);
  setTimeout(enhanceUserContent, 1000);
  
  $(".zone_cached_datetime").each(function() {
    if($(this).attr('title')) {
      var dt = $.parseFromISO($(this).attr('title'));
      if(dt.timestamp) {
        $(this).text(dt.datetime_formatted);
      }
    }
  });

  $(".show_sub_messages_link").click(function(event) {
    event.preventDefault();
    $(this).parents(".subcontent").find(".communication_sub_message.toggled_communication_sub_message").removeClass('toggled_communication_sub_message');
    $(this).parents(".communication_sub_message").remove();
  });
  $(".communication_message .message_short .read_more_link").click(function(event) {
    event.preventDefault();
    $(this).parents(".communication_message").find(".message_short").hide().end()
      .find(".message").show();
  });
  $(".communication_message .close_notification_link").live('click', function(event) {
    event.preventDefault();
    var $message = $(this).parents(".communication_message");
    $message.confirmDelete({
      url: $(this).attr('rel'),
      noMessage: true,
      success: function() {
        $(this).slideUp(function() {
          $(this).remove();
        });
      }
    });
  });
  $(".communication_message .add_entry_link").click(function(event) {
    event.preventDefault();
    var $message = $(this).parents(".communication_message");
    var $reply = $message.find(".reply_message").hide();
    var $response = $message.find(".communication_sub_message.blank").clone(true).removeClass('blank');
    $reply.before($response.show());
    var id = $.uniqueId("textarea_");
    $response.find("textarea.rich_text").attr('id', id);
    $(document).triggerHandler('richTextStart', $("#" + id));
    $response.find("textarea:first").focus().select();
  });
  $(document).bind('richTextStart', function(event, $editor) {
    if(!$editor || $editor.length === 0) { return; }
    $editor = $($editor);
    if(!$editor || $editor.length === 0) { return; }
    $editor.editorBox();
    $editor.editorBox('focus', true);
    if(wikiSidebar) {
      wikiSidebar.attachToEditor($editor);
      $("#sidebar_content").hide();
      wikiSidebar.show();
    }
  }).bind('richTextEnd', function(event, $editor) {
    if(!$editor || $editor.length === 0) { return; }
    $editor = $($editor);
    if(!$editor || $editor.length === 0) { return; }
    $editor.editorBox('destroy');
    if(wikiSidebar) {
      $("#sidebar_content").show();
      wikiSidebar.hide();
    }
  });
  
  $(".cant_record_link").click(function(event) {
    event.preventDefault();
    $("#cant_record_dialog").dialog('close').dialog({
      autoOpen: false,
      modal: true,
      title: "Can't Create Recordings?",
      width: 400
    }).dialog('open');
  });
  
  $(".communication_message .content .links .show_users_link,.communication_message .header .show_users_link").click(function(event) {
    event.preventDefault();
    $(this).parents(".communication_message").find(".content .users_list").slideToggle();
  });
  $(".communication_message .delete_message_link").click(function(event) {
    event.preventDefault();
    $(this).parents(".communication_message").confirmDelete({
      noMessage: true,
      url: $(this).attr('href'),
      success: function() {
        $(this).slideUp();
      }
    });
  });
  $(".communication_sub_message .add_sub_message_form").formSubmit({
    beforeSubmit: function(data) {
      $(this).find("button").attr('disabled', true);
      $(this).find(".submit_button").text("Posting Message...");
      $(this).loadingImage();
    },
    success: function(data) {
      $(this).loadingImage('remove');
      var $message = $(this).parents(".communication_sub_message");
      if($(this).hasClass('submission_comment_form')) {
        var user_id = $(this).getTemplateData({textValues: ['submission_user_id']}).submission_user_id;
        var submission = null;
        for(var idx in data) {
          var s = data[idx].submission;
          if(s.user_id == user_id) {
            submission = s;
          }
        }
        if(submission) {
          var comment = submission.submission_comments[submission.submission_comments.length - 1].submission_comment;
          comment.post_date = $.parseFromISO(comment.created_at).datetime_formatted;
          comment.message = comment.formatted_body || comment.comment;
          $message.fillTemplateData({
            data: comment,
            htmlValues: ['message']
          });
        }
      } else if($(this).hasClass('context_message_form')) {
        var message = data.context_message;
        message.post_date = $.parseFromISO(message.created_at).datetime_formatted;
        message.message = message.formatted_body;
        
        $message.fillTemplateData({
          data: message,
          htmlValues: ['message']
        });
      } else {
        var entry = data.discussion_entry;
        entry.post_date = $.parseFromISO(entry.created_at).datetime_formatted;
        $message.find(".content > .message_html").val(entry.message);
        $message.fillTemplateData({
          data: entry,
          htmlValues: ['message']
        });
      }
      $message.find(".message").show();
      $message.find(".user_content").removeClass('enhanced');
      $message.parents(".communication_message").find(".reply_message").removeClass('lonely_behavior_message').show();
      $(document).triggerHandler('richTextEnd', $(this).find("textarea.rich_text"));
      $(document).triggerHandler('user_content_change');
      $(this).remove();
      if(location.href.match(/dashboard/)) {
        $.trackEvent('dashboard_comment', 'create');
      }
    },
    error: function(data) {
      $(this).loadingImage('remove');
      $(this).find("button").attr('disabled', false);
      $(this).find(".submit_button").text("Post Failed, Try Again");
      $(this).formErrors(data);
    }
  });
  $(".communication_sub_message form .cancel_button").click(function() {
    var $form = $(this).parents(".communication_sub_message");
    var $message = $(this).parents(".communication_message");
    $(document).triggerHandler('richTextEnd', $form.find("textarea.rich_text"));
    $form.remove();
    $message.find(".reply_message").show();
  });
  $(".communication_message,.communication_sub_message").bind('focusin mouseenter', function() {
    $(this).addClass('communication_message_hover');
  }).bind('focusout mouseleave', function(){
    $(this).removeClass('communication_message_hover');
  });
  $(".communication_sub_message .more_options_reply_link").click(function(event) {
    event.preventDefault();
    var $form = $(this).parents("form");
    var params = null;
    if($form.hasClass('submission_comment_form')) {
      params = {comment: ($form.find("textarea:visible:first").val() || "")};
    } else if($form.hasClass('context_message_form')) {
      var data = $form.getFormData({object_name: 'context_message'});
      params = {context_code: data.context_code, reply_id: data.root_context_message_id, body: data.body, recipients: data.recipients, subject: data.subject};
    } else {
      params = {message: ($form.find("textarea:visible:first").val() || "")};
    }
    location.href = $(this).attr('href') + (params ? JSON.stringify(params) : "");
  });
  $(".communication_message.new_activity_message").ifExists(function(){
    this.find(".message_type img").click(function() {
      var $this = $(this),
          c = $.trim($this.attr('class'));
      
      $this.parents(".message_type").find("img").removeClass('selected');
      
      $this
        .addClass('selected')
        .parents(".new_activity_message")
          .find(".message_type_text").text($this.attr('title')).end()
          .find(".activity_form").hide().end()
          .find("textarea, :text").val("").end()
          .find("." + c + "_form").show()
            .find(".context_select").change();
    });
    this.find(".context_select").change(function() {
      var $this = $(this),
          thisVal = $this.val(),
          $message = $this.parents(".communication_message"),
          $form = $message.find("form");
      $form.attr('action', $message.find("." + thisVal + "_form_url").attr('href'));
      $form.data('context_name', this.options[this.selectedIndex].text);
      $form.data('context_code', thisVal);
      $message.find(".roster_list").hide().find(":checkbox").each(function() { $(this).attr('checked', false); });
      $message.find("." + thisVal + "_roster_list").show();
    }).triggerHandler('change');
    this.find(".cancel_button").click(function(event) {
      $(this).parents(".communication_message").hide().prev(".new_activity_message").show();
    });
    this.find(".new_activity_message_link").click(function(event) {
      event.preventDefault();
      $(this).parents(".communication_message").hide().next(".new_activity_message")
        .find(".message_type img.selected").click().end()
        .show()
        .find(":text:visible:first").focus().select();
    });
    this.find("form.message_form").formSubmit({
      beforeSubmit: function(data) {
        $("button").attr('disabled', true);
        $("button.submit_button").text("Posting Message...");
      },
      success: function(data) {
        $("button").attr('disabled', false);
        $("button.submit_button").text("Post Message");
        var context_code = $(this).data('context_code') || "";
        var context_name = $(this).data('context_name') || "";
        if($(this).hasClass('discussion_topic_form')) {
          var topic = data.discussion_topic;
          topic.context_code = context_name;
          topic.user_name = $("#identity .user_name").text();
          topic.post_date = $.parseFromISO(topic.created_at).datetime_formatted;
          topic.topic_id = topic.id;
          var $template = $(this).parents(".communication_message").find(".template");
          var $message = $template.find(".communication_message").clone(true);
          $message.find(".header .title,.behavior_content .less_important a").attr('href', $template.find("." + context_code + "_topic_url").attr('href'));
          $message.find(".add_entry_link").attr('href', $template.find("." + context_code + "_topics_url").attr('href'));
          $message.find(".user_name").attr('href', $template.find("." + context_code + "_user_url").attr('href'));
          $message.find(".topic_assignment_link,.topic_assignment_url").attr('href', $template.find("." + context_code + "_assignment_url").attr('href'));
          $message.find(".attachment_name,.topic_attachment_url").attr('href', $template.find("." + context_code + "_attachment_url").attr('href'));
          var entry = {discussion_topic_id: topic.id};
          $message.fillTemplateData({
            data: topic,
            hrefValues: ['topic_id', 'user_id', 'assignment_id', 'attachment_id'],
            avoid: '.subcontent'
          });
          $message.find(".subcontent").fillTemplateData({
            data: entry,
            hrefValues: ['topic_id', 'user_id']
          });
          $message.find(".subcontent form").attr('action', $template.find("." + context_code + "_entries_url").attr('href'));
          $message.fillFormData(entry, {object_name: 'discussion_entry'});
          $(this).parents(".communication_message").after($message.hide());
          $message.slideDown();
          $(this).parents(".communication_message").slideUp();
          $(this).parents(".communication_message").prev(".new_activity_message").slideDown();
        } else if($(this).hasClass('announcement_form')) { // do nothing
        } else if($(this).hasClass('context_message_form')) { // do nothing
        } else {
          location.reload();
        }
      },
      error: function(data) {
        $("button").attr('disabled', false);
        $("button.submit_button").text("Post Failed, please try again");
        $(this).formErrors(data);
      }
    });
  });
  $("#topic_list .show_all_messages_link").show().click(function(event) {
    event.preventDefault();
    $("#topic_list .topic_message").show();
    $(this).hide();
  });
  
  // vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv
  // vvvvvvvvvvvvvvvvv BEGIN stuf form making pretty dates vvvvvvvvvvvvvvvvvv
  // vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv
  var timeZoneOffset = parseInt($("#time_zone_offset").text(), 10),
      timeAgoEvents  = [];
  function timeAgoRefresh() {
    timeAgoEvents = $(".time_ago_date:visible").toArray();
    processNextTimeAgoEvent();
  }
  function processNextTimeAgoEvent() {
    var eventElement = timeAgoEvents.shift();
    if (eventElement) {
      var $event = $(eventElement),
          originalDate = $event.data('original_date') || "",
          date = $event.data('parsed_date') || ( originalDate ? 
                    Date.parse(originalDate.replace(/ (at|by)/, "")) : 
                    Date.parse(($event.text() || "").replace(/ (at|by)/, "")) );
      if (date) {
        var now = new Date();
        now.setDate(now.getDate() + 1);
        if (!originalDate && date > now && date - now > 3600000) {
          var year = date.getUTCFullYear().toString();
          if(date > now && date.getUTCFullYear() == now.getUTCFullYear() && !$event.text().match(year)) {
            date.setUTCFullYear(date.getUTCFullYear() - 1);
          }
        }
        var timeZoneDiff = now.getTimezoneOffset() - timeZoneOffset;
        if(isNaN(timeZoneDiff)) { timeZoneDiff = 0; }
        var diff = now - date + (timeZoneDiff * 60 * 1000);
        $event.data('original_date', date.toString("MMM d, yyyy h:mmtt"));
        $event.data('parsed_date', date);
        // This line would compensate for a user who set their time zone to something
        //   different than the time zone setting on the current computer.  It would adjust
        //   the times displayed to match the time zone of the current computer.  This could
        //   be confusing for a student since due dates and things will NOT be adjusted,
        //   so dates and times will not match up.
        // date = date.addMinutes(-1 * timeZoneDiff);
        var defaultDateString = date.toString("MMM d, yyyy") + date.toString(" h:mmtt").toLowerCase();
        var dateString = defaultDateString;
        if(diff < (24 * 3600 * 1000)) { //date > now.addHours(-24)) {
          if(diff < (3600 * 1000)) { //date > now.addHours(-1)) {
            if(diff < (60 * 1000)) { //date > now.addMinutes(-1)) {
              dateString = "less than a minute ago";
            } else {
              var minutes = parseInt(diff / (60 * 1000), 10);
              dateString = minutes + " minute" + (minutes > 1 ? "s" : "") + " ago";
            }
          } else {
            var hours = parseInt(diff / (3600 * 1000), 10);
            dateString = hours + " hour" + (hours > 1 ? "s" : "") + " ago";
          }
        }
        $event.text(dateString);
        $event.attr('title', defaultDateString);
      }
      setTimeout(processNextTimeAgoEvent, 1);
    } else {
      setTimeout(timeAgoRefresh, 60000);
    }
  }
  setTimeout(timeAgoRefresh, 100);
  // ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  // ^^^^^^^^^^^^^^^^^^ END stuff for making pretty dates ^^^^^^^^^^^^^^^^^^^
  // ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  
  var sequence_url = $('#sequence_footer .sequence_details_url').filter(':last').attr('href');
  if (sequence_url) {
    $.ajaxJSON(sequence_url, 'GET', {}, function(data) {
      var $sequence_footer = $('#sequence_footer');
      if (data.current_item) {
        $('#sequence_details .current').fillTemplateData({data: data.current_item.content_tag});
        $.each({previous:'.prev', next:'.next'}, function(label, cssClass) {
          var $link = $sequence_footer.find(cssClass);
          if (data[label + '_item'] || data[label + '_module']) {
            var tag = (data[label + '_item']    && data[label + '_item'].content_tag) ||
                      (data[label + '_module']  && data[label + '_module'].context_module);
            
            if (!data[label + '_item']) {
              tag.title = tag.title || tag.name;
              tag.text = $.capitalize(label) + ' Module';
              $link.addClass('module_button');
            }
            $link.fillTemplateData({ data: tag });
            if (data[label + '_item']) {
              $link.attr('href', $.replaceTags($sequence_footer.find('.module_item_url').attr('href'), 'id', tag.id));
            } else {
              $link.attr('href', $.replaceTags($sequence_footer.find('.module_url').attr('href'), 'id', tag.id) + '/items/' + (label === 'previous' ? 'last' : 'first'));
            }
          } else {
            $link.hide();
          }
        });
        $sequence_footer.show();
      }
    });
  }
  
  $(".module_legend_link").click(function(event) {
    var $mod = $(this).parents(".module_legend");
    $mod.hide();
    $mod.next(".module_legend").show();
  });
  
  var $wizard_box = $("#wizard_box");
  
  function setWizardSpacerBoxDispay(action){
    $("#wizard_spacer_box").height($wizard_box.height() || 0).showIf(action === 'show');
  }
  
  var pathname = window.location.pathname;
  $(".close_wizard_link").click(function(event) {
    event.preventDefault();
    $.store.userSet('hide_wizard_' + pathname, true);
    $wizard_box.slideUp('fast', function() {
      $(".wizard_popup_link").slideDown('fast');
      setWizardSpacerBoxDispay('hide');
    });
  });
  
  $(".wizard_popup_link").click(function(event) {
    event.preventDefault();
    $(".wizard_popup_link").slideUp('fast');
    $wizard_box.slideDown('fast', function() {
      $wizard_box.triggerHandler('wizard_opened');
      $([document, window]).triggerHandler('scroll');
    });
  });
  
  $wizard_box.ifExists(function($wizard_box){
    
    $wizard_box.bind('wizard_opened', function() {
      var $wizard_options = $wizard_box.find(".wizard_options"),
          height = $wizard_options.height();
      $wizard_options.height(height);
      $wizard_box.find(".wizard_details").css({
        maxHeight: height - 5,
        overflow: 'auto'
      });
      setWizardSpacerBoxDispay('show');
    });
    
    $wizard_box.find(".wizard_options_list .option").click(function(event) {
      var $this = $(this);
      var $a = $(event.target).closest("a");
      if($a.length > 0 && $a.attr('href') != "#") { return; }
      event.preventDefault();
      $this.parents(".wizard_options_list").find(".option.selected").removeClass('selected');
      $this.addClass('selected');
      var $details = $wizard_box.find(".wizard_details");
      var data = $this.getTemplateData({textValues: ['header']});
      data.link = "Click to " + data.header;
      $details.fillTemplateData({ 
        data: data
      });
      $details.find(".details").remove();
      $details.find(".header").after($this.find(".details").clone(true).show());
      var url = $this.find(".header").attr('href');
      if(url != "#") {
        $details.find(".link").show().attr('href', url);
      } else {
        $details.find(".link").hide();
      }
      $details.hide().fadeIn('fast');
    });
    setTimeout(function() {
      if(!$.store.userGet('hide_wizard_' + pathname)) {
        $(".wizard_popup_link.auto_open:first").click();
      }
    }, 500);
  });
  
  // this is for things like the to-do, recent items and upcoming, it 
  // happend a lot so rather than duplicating it everywhere I stuck it here
  $(".more_link").click(function(event) {
    $(this).closest("li").slideUp().parents("ul").children(":hidden").slideDown().first().find(":tabbable:first").focus();
    return false;
  });
  $(".to-do-list").delegate('.disable_item_link', 'click', function(event) {
    event.preventDefault();
    var $item = $(this).parents("li");
    var url = $(this).attr('href');
    function remove(delete_url) {
      $item.confirmDelete({
        url: delete_url,
        noMessage: true,
        success: function() {
          $(this).slideUp(function() {
            $(this).remove();
          });
        }
      });
    }
    if($(this).hasClass('grading')) {
      $(this).dropdownList({
        options: {
          '<span class="ui-icon ui-icon-trash">&nbsp;</span> Ignore Forever': function() {
            remove(url + "?permanent=1");
          },
          '<span class="ui-icon ui-icon-star">&nbsp;</span> Ignore Until New Submission': function() {
            remove(url);
          }
        }
      });
    } else {
      remove(url + "?permanent=1");
    }
  });
  // if there is not a h1 or h2 on the page, then stick one in there for accessibility.
  if (!$('h1').length) {
    $('<h1 class="ui-helper-hidden-accessible">' + document.title + '</h1>').prependTo('#content');
  }
  if(!$('h2').length && $('#breadcrumbs li:last').text().length ) {
    var $h2 = $('<h2 class="ui-helper-hidden-accessible">' + $('#breadcrumbs li:last').text() + '</h2>'),
        $h1 = $('#content h1');
    $h1.length ? 
      $h1.after($h2) : 
      $h2.prependTo('#content');
  }

  // in 2 seconds (to give time for everything else to load), find all the external links and add give them
  // the external link look and behavior (force them to open in a new tab)
  setTimeout(function() {
    $("#content a:external,#content a.explicit_external_link").each(function(){
      $(this)
        .not(":has(img)")
        .not(".not_external")
        .addClass('external')
        .children("span.ui-icon-extlink").remove().end()
        .html('<span>' + $(this).html() + '</span>')
        .attr('target', '_blank')
        .append('<span class="ui-icon ui-icon-extlink ui-icon-inline" title="Links to an external site."/>');
    });
  }, 2000);
  
});
