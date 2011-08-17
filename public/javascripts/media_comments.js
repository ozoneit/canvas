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

(function($, INST){
  var yourVersion = null;
  try {
    yourVersion = swfobject.getFlashPlayerVersion().major + "." + swfobject.getFlashPlayerVersion().minor;
    yourVersion = " (you have " + yourVersion + " installed)";
  } catch(e) {
  }
  var flashRequiredMessage = "<div>This video requires Flash version 9 or higher" + yourVersion + ".  <br/><a target='_blank' href='http://get.adobe.com/flashplayer/'>Click here to upgrade</a></div>";
  $.fn.mediaComment = function(command, arg1, arg2, arg3, arg4, arg5) {
    var id = arg1, mediaType = arg2, downloadUrl = arg3;
    if(!INST.kalturaSettings) { console.log('Kaltura has not been enabled for this account'); return; }
    if(command == 'create') {
      mediaType = arg1;
      var callback = arg2;
      var cancel_callback = arg3;
      var modal = arg4;
      var defaultTitle = arg5;
      $("#media_recorder_container").removeAttr('id').addClass('old_recorder_container');
      this.attr('id', 'media_recorder_container').removeClass('old_recorder_container');
      this.unbind('media_comment_created');
      var $comment = this;
      this.bind('media_comment_created', function(event, data) {
        callback.call(this, data.id, data.mediaType);
      });
      if(location.href.match(/kaltura_test/)) {
        $.mediaComment.init(mediaType, {
          modal: modal,
          close: function() {
            if(cancel_callback && $.isFunction(cancel_callback)) {
              cancel_callback.call($comment);
            }
          },
          defaultTitle: defaultTitle
        });
      } else { 
        var $dialog = $("#media_comment_create_dialog");
        if($dialog.length === 0) {
          $dialog = $("<div id='media_comment_create_dialog'/>");
          $("body").append($dialog);
        }
        $dialog.dialog('close').dialog({
          autoOpen: false,
          title: "Add Media Comment",
          width: 570,
          height: 370,
          draggable: true,
          modal: !!arg4,
          close: function() {
            if(cancel_callback && $.isFunction(cancel_callback)) {
              cancel_callback.call($comment);
            }
          }
        }).dialog('open');
        $dialog.empty();
        $dialog.append("<div id='media_comment_create' style='font-size: 1.5em;'>Loading...</div>");
        var commentReady = function() {
          var params = {
            allowScriptAccess: 'always',
            allowNetworking: 'all',
            wmode: 'opaque'
          }
          var flashVars = {
            partnerId: INST.kalturaSettings.partner_id,
            subpId: INST.kalturaSettings.subpartner_id,
            uid: INST.kaltura_user_id || 'ANONYMOUS',
            ks: INST.kaltura_session_id,
            kshowId: -1,
            afterAddEntry: 'mediaCommentCallback',
            singleContribution: 'true',
            enableTagging: 'false',
            showCloseButton: 'false',
            partnerData: $.mediaComment.partnerData(),
            partner_data: $.mediaComment.partnerData(),
            wmode: 'opaque'
          }
          $("#media_comment_create").html(flashRequiredMessage)
          swfobject.embedSWF("http://" + INST.kalturaSettings.domain + "/kcw/ui_conf_id/" + INST.kalturaSettings.kcw_ui_conf, "media_comment_create", "540", "300", "9.0.0", false, flashVars, params);
          if($("#cant_record_dialog .links").length > 0) {
            var $links = $("#cant_record_dialog .links").clone(true);
            $dialog.append($links.show());
          }
        };
        if(INST && INST.kaltura_session_id) {
          commentReady();
        } else {
          $.ajaxJSON('/dashboard/comment_session', 'GET', {}, function(data) {
            INST = INST || {};
            INST.kaltura_session_id = data.ks;
            INST.kaltura_user_id = data.uid;
            commentReady();
          }, function(data) {
            if(data.logged_in == false) {
              $dialog.text("You must be logged in to record media.");
            } else {
              $dialog.text("Media Comment Application failed to load.  Please try again.");
            }
          });
        }
      }
    } else if(command == 'show_inline') {
      var $div = $("<span/>");
      if(mediaType != 'video' && mediaType != 'audio') {
        if($(this).hasClass('audio_playback')) { 
          mediaType = 'audio';
        } else {
          mediaType = 'video';
        }
      }
      $div.attr('id', 'media_comment_holder_' + Math.round(Math.random() * 10000));
      var $holder = $(this);
      if($(this).parent(".instructure_file_link_holder").length > 0) {
        $holder = $(this).parent(".instructure_file_link_holder");
      }
      var showInline = function(id) {
        $holder.append($div);
        var width = $holder.width();
        var flashVars = {};
        var params = {
          allowScriptAccess: 'always',
          allowNetworking: 'all',
          allowFullScreen: true,
          bgcolor: "#000000",
          wmode: 'opaque'
        };
        var url = "/media_objects/" + id + "/redirect";
        var width = Math.min($holder.closest("div,p,table").width() || 550, 550);
        var height = width / 550 * 448;
        if(mediaType == 'audio') {
          height = 125;
          width = Math.min(width, 350);
        }
        swfobject.embedSWF(url, $div.attr('id'), width.toString(), height.toString(), "9.0.0", false, flashVars, params);
      }
      if(id == 'maybe') {
        var detailsUrl = downloadUrl.replace(/\/download.*/, "");
        $holder.text("Loading...");
        $.ajaxJSON(detailsUrl, 'GET', {}, function(data) {
          if(data.attachment && data.attachment.media_entry_id && data.attachment.media_entry_id != 'maybe') {
            $holder.text("");
            showInline(data.attachment.media_entry_id);
          } else {
            $holder.text("This media file failed to load");
          }
        }, function() {
          $holder.text("This media file failed to load");
        });
      } else {
        showInline(id);
      }
    } else if(command == 'show') {
      var width = this.width();
      var flashVars = {};
      var params = {
        allowScriptAccess: 'always',
        allowNetworking: 'all',
        allowFullScreen: true,
        bgcolor: "#000000"
      };
      var url = "/media_objects/" + id + "/redirect";
      var $dialog = $("#media_comment_player_dialog");
      if($dialog.length === 0) {
        $dialog = $("<div id='media_comment_player_dialog'/>");
        $("body").append($dialog);
      }
      $dialog.dialog('close').dialog({
        autoOpen: false,
        title: "Play Media Comment",
        width: 575,
        height: 493,
        modal: true,
        draggable: false,
        wmode: 'opaque'
      }).dialog('open');
      $dialog.empty();
      $dialog.append("<div id='media_comment_play'/>");
      $dialog.find("#media_comment_play").html(flashRequiredMessage);
      swfobject.embedSWF(url, 'media_comment_play', "550", "448", "9.0.0", false, flashVars, params);
    }
    return this;
  };
  var thumbnailsQueued = [];
  var thumbnailing = false;
  var nextThumbnail = function() {
    thumbnailing = true;
    for(var idx = 0; idx < 30; idx++) {
      var thumbnail = thumbnailsQueued.shift();
      if(thumbnail) {
        var $elem = thumbnail.elem;
        var size = thumbnail.size;
        $elem.createMediaCommentThumbnail(thumbnail);
      }
    }
    if(thumbnailsQueued.length > 0) {
      setTimeout(nextThumbnail, 500);
    } else {
      thumbnailing = false;
    }
  }
  $.fn.mediaCommentThumbnail = function(size, keepOriginalText) {
    $(this).each(function() {
      thumbnailsQueued.push({size: size, elem: $(this), keepOriginalText: keepOriginalText});
    });
    if(!thumbnailing) {
      thumbnailing = true;
      setTimeout(nextThumbnail, 500);
    }
    return this;
  }
  $.fn.createMediaCommentThumbnail = function(opts) {
    if(!INST.kalturaSettings) { console.log('Kaltura has not been enabled for this account'); return; }
    var size = opts.size || 'normal';
    var only_show_icon = opts.only_show_icon;
    var keep_original_text = opts.keepOriginalText;
    var dimensions = $.fn.mediaCommentThumbnail.sizes[size] || $.fn.mediaCommentThumbnail.sizes['normal'];
    this.each(function() {
      var id = $.trim($(this).find(".media_comment_id:first").text());
      if(!id && $(this).attr('id') && $(this).attr('id').match(/^media_comment_/)) {
        id = $(this).attr('id').substring(14);
      }
      id = id || $.trim($(this).parent().find(".media_comment_id:first").text());
      if(id) {
        var url = "http://" + INST.kalturaSettings.resource_domain + "/p/" + INST.kalturaSettings.partner_id + "/thumbnail/entry_id/";
        url = url + id;
        url = url + "/width/" + dimensions.width + "/height/" + dimensions.height + "/bgcolor/000000/type/2/vid_sec/5";
        var $img = $("<img/>");
        $img.addClass('media_comment_thumbnail');
        $img.addClass('media_comment_thumbnail-' + size);
        if(only_show_icon) {
          $img.attr('src', '/images/media_comment.png');
        } else {
          $img.attr('src', '/images/blank.png');
          $(this).addClass('no-hover').addClass('no-underline');
          $img.hover(function() {
            $img.attr('src', '/images/play_overlay.png');
          }, function() {
            $img.attr('src', '/images/blank.png');
          });
        }
        $img.css('backgroundImage', 'url(' + url + ')');
        $img.attr('title', 'Click to View');
        var $a = $(this);
        if(!keep_original_text) {
          $(this).empty();
        } else {
          var $a = $(this).clone().empty().removeClass('instructure_file_link');
          if($(this).parent(".instructure_file_link_holder").length > 0) {
            $(this).parent(".instructure_file_link_holder").append($a);
          } else {
            $(this).after($a);
          }
        }
        $a.addClass('instructure_inline_media_comment');
        $a.append($img).css({
          backgroundImage: '',
          padding: 0
        });
        $(this).append("<span class='media_comment_id' style='display: none;'>" + id + "</span>");
      }
    });
    return this;
  };
  $.fn.mediaCommentThumbnail.sizes = {
    normal: {width: 140, height: 100},
    small: {width: 70, height: 50}
  };
  $.mediaComment = function(command, arg1, arg2) {
    var $container = $("<div/>")
    $("body").append($container.hide());
    $.fn.mediaComment.apply($container, arguments);
  }
  $.mediaComment.partnerData = function(params) {
    params = params || {};
    params.context_code = $.mediaComment.contextCode();
    params.root_account_id = parseInt($("#domain_root_account_id").text(), 10) || 0;
    return JSON.stringify(params);
  }
  $.mediaComment.contextCode = function() {
    var code = "";
    try {
      code = $.trim($("#current_context_code").text()) || $.trim("user_" + $("#identity .user_id").text());
    } catch(e) { }
    return code;
  }

  var addedEntryIds = {};
  $.mediaComment.entryAdded = function(entryId, entryType, title, userTitle) {
    if(!entryId || addedEntryIds[entryId]) { return; }
    addedEntryIds[entryId] = true;
    var entry = {
      mediaType: entryType,
      entryId: entryId,
      title: title,
      userTitle: userTitle
    }
    var context_code = $.mediaComment.contextCode();
    if(entry.mediaType == 1 || entry.mediaType == 2 || entry.mediaType == 5 || true) {
      var mediaType = 'video';
      if(entry.mediaType == 2) {
        mediaType = 'image';
      } else if(entry.mediaType == 5) {
        mediaType = 'audio';
      }
      if(context_code) {
        $.ajaxJSON("/media_objects", "POST", {
            id: entry.entryId,
            type: mediaType,
            context_code: context_code,
            title: entry.title,
            user_entered_title: entry.userTitle
        }, function(data) {
          $(document).triggerHandler('media_object_created', data);
        }, function(data) {});
      }
      $("#media_recorder_container").triggerHandler('media_comment_created', {id: entry.entryId, mediaType: mediaType}); 
    }
  };
  $.mediaComment.audio_delegate = {
    readyHandler: function() {
      $("#audio_upload")[0].setMediaType('audio');
    },
    selectHandler: function() {
      $.mediaComment.upload_delegate.selectHandler('audio');
    },
    singleUploadCompleteHandler: function(entries) {
      $.mediaComment.upload_delegate.singleUploadCompleteHandler('audio', entries);
    },
    allUploadsCompleteHandler: function() {
      $.mediaComment.upload_delegate.allUploadsCompleteHandler('audio');
    },
    entriesAddedHandler: function(entries) {
      $.mediaComment.upload_delegate.entriesAddedHandler('audio', entries);
    },
    progressHandler: function(loaded_bytes, total_bytes, entry) {
      $.mediaComment.upload_delegate.progressHandler('audio', loaded_bytes, total_bytes, entry);
    }
  };
  $.mediaComment.video_delegate = {
    readyHandler: function() {
      $("#video_upload")[0].setMediaType('video');
    },
    selectHandler: function() {
      $.mediaComment.upload_delegate.selectHandler('video');
    },
    singleUploadCompleteHandler: function(entries) {
      $.mediaComment.upload_delegate.singleUploadCompleteHandler('video', entries);
    },
    allUploadsCompleteHandler: function() {
      $.mediaComment.upload_delegate.allUploadsCompleteHandler('video');
    },
    entriesAddedHandler: function(entries) {
      $.mediaComment.upload_delegate.entriesAddedHandler('video', entries);
    },
    progressHandler: function(loaded_bytes, total_bytes, entry) {
      $.mediaComment.upload_delegate.progressHandler('video', loaded_bytes, total_bytes, entry);
    }
  }
  $.mediaComment.upload_delegate = {
    currentType: 'audio',
    submit: function() {
      var type = $.mediaComment.upload_delegate.currentType;
      var files = $("#" + type + "_upload")[0].getFiles();
      if(files.length > 1) {
        $("#" + type + "_upload")[0].removeFiles(0, files.length - 2);
      }
      files = $("#" + type + "_upload")[0].getFiles();
      if(files.length == 0) {
        return;
      }
      $("#media_upload_progress").css('visibility', 'visible').progressbar({value: 1});
      $("#media_upload_submit").attr('disabled', true).text("Submitting Media File...");
      $("#" + type + "_upload")[0].upload();
    },
    selectHandler: function(type) {
      $.mediaComment.upload_delegate.currentType = type;
      var files = $("#" + type + "_upload")[0].getFiles();
      if(files.length > 1) {
        $("#" + type + "_upload")[0].removeFiles(0, files.length - 2);
      }
      var file = $("#" + type + "_upload")[0].getFiles()[0];
      $("#media_upload_settings .icon").attr('src', '/images/file-' + type + '.png');
      $("#media_upload_submit").attr('disabled', file ? false : true)
      $("#media_upload_settings").css('visibility', file ? 'visible' : 'hidden');
      $("#media_upload_title").val(file.title);
      $("#media_upload_display_title").text(file.title);
      $("#media_upload_file_size").text($.fileSize(file.bytesTotal));
      $("#media_upload_title").focus().select();
    },
    singleUploadCompleteHandler: function(type, entries) {
      $("#media_upload_progress").progressbar('option', 'value', 100);
    },
    allUploadsCompleteHandler: function(type) {
      $("#media_upload_progress").progressbar('option', 'value', 100);
      $("#" + type + "_upload")[0].addEntries();
    },
    entriesAddedHandler: function(type, entries) {
      $("#media_upload_progress").progressbar('option', 'value', 100);
      var entry = entries[0];
      $("#media_upload_submit").text("Submitted Media File!");
      setTimeout(function() {
        $("#media_comment_dialog").dialog('close');
      }, 1500);
      if(type == 'audio') {
        entry.entryType = 5;
      } else if(type == 'video') {
        entry.entryType = 1;
      }
      $.mediaComment.entryAdded(entry.entryId, entry.entryType, entry.title);
    },
    progressHandler: function(type, loaded_bytes, total_bytes, entry) {
      var pct = 100.0 * loaded_bytes / total_bytes;
      $("#media_upload_progress").progressbar('option', 'value', pct);
    }
  }
  var reset_selectors = false;
  var lastInit = null;
  $.mediaComment.init = function(media_type, opts) {
    lastInit = lastInit || new Date();
    media_type = media_type || "any";
    opts = opts || {};
    var user_name = $.trim($("#identity .user_name").text() || "");
    if(user_name) {
      user_name = user_name + ": " + (new Date()).toString("ddd MMM d, yyyy");
    }
    var defaultTitle = opts.defaultTitle ||  user_name || "Media Contribution";
    var mediaCommentReady = function() {
      $("#video_record_title,#audio_record_title").val(defaultTitle);
      $dialog.dialog('close').dialog({
        autoOpen: false,
        title: "Record/Upload Media Comment",
        width: 460,
        height: 385,
        modal: (opts.modal == false ? false : true)
      }).dialog('open');
      $dialog.dialog('option', 'close', function() {
        if(opts && opts.close && $.isFunction(opts.close)) {
          opts.close.call($dialog);
        }
      });
      var ks = $dialog.data('ks');

      if(media_type == "video") {
        $("#video_record_option").click();
        $("#media_record_option_holder").hide();
        $("#audio_upload_holder").hide();
        $("#video_upload_holder").show();
      } else if(media_type == "audio") {
        $("#audio_record_option").click();
        $("#media_record_option_holder").hide();
        $("#audio_upload_holder").show();
        $("#video_upload_holder").hide();
      } else {
        $("#video_record_option").click();
        $("#audio_upload_holder").show();
        $("#video_upload_holder").show();
      }
      // re-set the state on everything.  Basically just clear the uploader
      // files list, remove the uploader progress bar and re-set the submit button.
      // Re-set the recorders, too?  I guess probably, yeah, if you can.
      $(document).triggerHandler('reset_media_comment_forms');
      var temporaryName = $.trim($("#identity .user_name").text()) + " " + (new Date()).toISOString();
      var flashVars = {
        host:INST.kalturaSettings.domain,
        kshowId:"-1",
        pid:INST.kalturaSettings.partner_id,
        subpid:INST.kalturaSettings.subpartner_id,
        uid:$dialog.data('uid') || "ANONYMOUS",
        ks:ks,
        partnerData: $.mediaComment.partnerData(),
        partner_data: $.mediaComment.partnerData(),
        themeUrl:"/media_test/skin.swf",
        localeUrl:"/media_test/locale.xml",
        entryName:temporaryName,
        thumbOffset:"1",
        licenseType:"CC-0.1",
        showUi:"true",
        useCamera:"false",
        maxFileSize: 50,
        maxUploads: 1
      }
      var params = {
        "align": "middle",
        "quality": "high",
        "bgcolor": "#ffffff",
        "name": "KRecordAudio",
        "allowScriptAccess":"sameDomain",
        "type": "application/x-shockwave-flash",
        "pluginspage": "http://www.adobe.com/go/getflashplayer",
        "wmode": "opaque"
      }
      $("#audio_record").html("Flash required for recording audio.")
      swfobject.embedSWF("/media_test/KRecordAudio.swf", "audio_record", "320", "240", "9.0.0", false, flashVars, params);

      var params = $.extend({}, params, {name: 'KRecordVideo'})
      $("#video_record").html("Flash required for recording video.")
      swfobject.embedSWF("/media_test/KRecordVideo.swf", "video_record", "320", "240", "9.0.0", false, flashVars, params);

      var flashVars = {
        host:"http://" + INST.kalturaSettings.domain,
        partnerId:INST.kalturaSettings.partner_id,
        subPId:INST.kalturaSettings.subpartner_id,
        partnerData: $.mediaComment.partnerData(),
        partner_data: $.mediaComment.partnerData(),
        uid:$dialog.data('uid') || "ANONYMOUS",
        entryId: "-1",
        ks:ks,
        thumbOffset:"1",
        licenseType:"CC-0.1",
        maxFileSize: 50,
        maxUploads: 1,
        uiConfId: INST.kalturaSettings.upload_ui_conf,
        jsDelegate: "$.mediaComment.audio_delegate"
      }
      var params = {
        "align": "middle",
        "quality": "high",
        "bgcolor": "#ffffff",
        "name": "KUpload",
        "allowScriptAccess":"always",
        "type": "application/x-shockwave-flash",
        "pluginspage": "http://www.adobe.com/go/getflashplayer",
        "wmode": "transparent"
      }
      $("#audio_upload").html("Flash required for uploading audio.");
      var width = "180";
      var height = "50";
      swfobject.embedSWF("/media_test/KUpload.swf", "audio_upload", width, height, "9.0.0", false, flashVars, params)
      
      flashVars = $.extend({}, flashVars, {jsDelegate: '$.mediaComment.video_delegate'});
      $("#video_upload").html("Flash required for uploading video.");
      var width = "180";
      var height = "50";
      swfobject.embedSWF("/media_test/KUpload.swf", "video_upload", width, height, "9.0.0", false, flashVars, params)
      
      
      var $audio_record_holder, $audio_record, $audio_record_meter;
      var audio_record_counter, current_audio_level, audio_has_volume;
      var $video_record_holder, $video_record, $video_record_meter;
      var video_record_counter, current_video_level, video_has_volume = false;
      reset_selectors = true;
      setInterval(function() {
        if(reset_selectors) {
          $audio_record_holder = $("#audio_record_holder");
          $audio_record = $("#audio_record");
          $audio_record_meter = $("#audio_record_meter");
          audio_record_counter = 0;
          current_audio_level = 0;
          $video_record_holder = $("#video_record_holder");
          $video_record = $("#video_record");
          $video_record_meter = $("#video_record_meter");
          video_record_counter = 0;
          current_video_level = 0;
          reset_selectors = false;
        }
        audio_record_counter++;
        video_record_counter++;
        var audio_level = null, video_level = null;
        if($audio_record && $audio_record[0] && $audio_record[0].getMicophoneActivityLevel) {
          audio_level = $audio_record[0].getMicophoneActivityLevel();
        } else {
          $audio_record = $("#audio_record");
        }
        if($video_record && $video_record[0] && $video_record[0].getMicophoneActivityLevel) {
          video_level = $video_record[0].getMicophoneActivityLevel();
        } else {
          $video_record = $("#video_record");
        }
        if(audio_level != null) { 
          audio_level = Math.max(audio_level, current_audio_level);
          if(audio_level > -1 && !$audio_record_holder.hasClass('with_volume')) {
            $audio_record_meter.css('display', 'none');
            $("#audio_record_holder").addClass('with_volume').animate({'width': 340}, function() {
              $audio_record_meter.css('display', '');
            });
          }
          if(audio_record_counter > 4) {
            current_audio_level = 0;
            audio_record_counter = 0;
            var band = (audio_level - (audio_level % 10)) / 10;
            $audio_record_meter.attr('class', 'volume_meter band_' + band);
          } else {
            current_audio_level = audio_level;
          }
        }
        if(video_level != null) { 
          video_level = Math.max(video_level, current_video_level);
          if(video_level > -1 && !$video_record_holder.hasClass('with_volume')) {
            $video_record_meter.css('display', 'none');
            $("#video_record_holder").addClass('with_volume').animate({'width': 340}, function() {
              $video_record_meter.css('display', '');
            });
          }
          if(video_record_counter > 4) {
            current_video_level = 0;
            video_record_counter = 0;
            var band = (video_level - (video_level % 10)) / 10;
            $video_record_meter.attr('class', 'volume_meter band_' + band);
          } else {
            current_video_level = video_level;
          }
        }
      }, 20);
    }
    var now = new Date();
    if((now - lastInit) > 300000) {
      $("#media_comment_dialog").dialog('close').remove();
    }
    lastInit = now;

    var $dialog = $("#media_comment_dialog");
    if($dialog.length == 0) {
      var $div = $("<div/>").attr('id', 'media_comment_dialog');
      $div.html("Loading...");
      $div.dialog('close').dialog({
        autoOpen: false,
        title: "Record/Upload Media Comment",
        width: 450,
        height: 300
      }).dialog('open');
      $.ajaxJSON('/dashboard/comment_session', 'GET', {}, function(data) {
        $div.data('ks', data.ks);
        $div.data('uid', data.uid);
      }, function(data) {
        if(data.logged_in == false) {
          $div.data('ks-error', "You must be logged in to record media.");
        } else {
          $div.data('ks-error', "Media Comment Application failed to load.  Please try again.");
        }
      });
      $.get("/partials/_media_comments.html", function(html) {
        var checkForKS = function() {
          if($div.data('ks')) {
            $div.html(html);
            $div.find("#media_record_tabs").tabs({
              select: function() {
                $(document).triggerHandler('reset_media_comment_forms');
              }
            });
            mediaCommentReady();
          } else if($div.data('ks-error')) {
            $div.html($div.data('ks-error'));
          } else {
            setTimeout(checkForKS, 500);
          }
        }
        checkForKS();
        $dialog = $("#media_comment_dialog");
      });
      $dialog = $div;
    } else {
      mediaCommentReady();
    }
  }
  $(document).ready(function() {
    $(document).bind('reset_media_comment_forms', function() {
      $("#audio_record_holder_message,#video_record_holder_message").removeClass('saving')
        .find(".recorder_message").html("Saving Recording...<img src='/images/media-saving.gif'/>");
      $("#audio_record_holder").stop(true, true).clearQueue().css('width', '').removeClass('with_volume');
      $("#video_record_holder").stop(true, true).clearQueue().css('width', '').removeClass('with_volume');
      $("#media_upload_submit").text("Submit Media File").attr('disabled', true);
      $("#media_upload_settings").css('visibility', 'hidden');
      $("#media_upload_progress").css('visibility', 'hidden').progressbar().progressbar('option', 'value', 1);
      $("#media_upload_title").val("");
      var files = $("#audio_upload")[0] && $("#audio_upload")[0].getFiles && $("#audio_upload")[0].getFiles();
      if(files && $("#audio_upload")[0].removeFiles && files.length > 0) {
        $("#audio_upload")[0].removeFiles(0, files.length - 1);
      }
      files = $("#video_upload")[0] && $("#video_upload")[0].getFiles && $("#video_upload")[0].getFiles();
      if(files && $("#video_upload")[0].removeFiles && files.length > 0) {
        $("#video_upload")[0].removeFiles(0, files.length - 1);
      }
   });
    $("#media_upload_submit").live('click', function(event) {
      $.mediaComment.upload_delegate.submit();
    });
    $("#video_record_option,#audio_record_option").live('click', function(event) {
      event.preventDefault();
      $("#video_record_option,#audio_record_option").removeClass('selected_option');
      $(this).addClass('selected_option');
      $("#audio_record_holder").stop(true, true).clearQueue().css('width', '').removeClass('with_volume');
      $("#video_record_holder").stop(true, true).clearQueue().css('width', '').removeClass('with_volume');
      if($(this).attr('id') == 'audio_record_option') {
        $("#video_record_holder_holder").hide();
        $("#audio_record_holder_holder").show();
      } else {
        $("#video_record_holder_holder").show();
        $("#audio_record_holder_holder").hide();
      }
    });
  });
  $(document).bind('media_recording_error', function() {
    $("#audio_record_holder_message,#video_record_holder_message").find(".recorder_message").html("Saving appears to have failed.  Please close this popup to try again.<div style='font-size: 0.8em; margin-top: 20px;'>If this problem keeps happening, you may want to try recording your media locally and then uploading the saved file instead.</div>");
  });
})(jQuery, INST);

function mediaCommentCallback(results) {
  var context_code = $.trim($("#current_context_code").text()) || $.trim("user_" + $("#identity .user_id").text());
  for(var idx in results) { 
    var entry = results[idx];
    if(entry.mediaType == 1 || entry.mediaType == 2 || entry.mediaType == 5 || true) {
      var mediaType = 'video';
      if(entry.mediaType == 2) {
        mediaType = 'image';
      } else if(entry.mediaType == 5) {
        mediaType = 'audio';
      }
      if(context_code) {
        $.ajaxJSON("/media_objects", "POST", {
            id: entry.entryId,
            type: mediaType,
            context_code: context_code,
            title: entry.name
        }, function(data) {
          $(document).triggerHandler('media_object_created', data);
        }, function(data) {});
      }
      $("#media_recorder_container").triggerHandler('media_comment_created', {id: entry.entryId, mediaType: mediaType}); 
    }
  }
  $("#media_comment_create_dialog").empty().dialog('close');
}
function beforeAddEntry() {
  var attemptId = Math.random();
  $.mediaComment.lastAddAttemptId = attemptId;
  setTimeout(function() {
    if($.mediaComment.lastAddAttemptId == attemptId) {
      $(document).triggerHandler('media_recording_error');
    }
  }, 300000);
  $("#audio_record_holder_message,#video_record_holder_message").addClass('saving');
}
function addEntryFail() {
  $(document).triggerHandler('media_recording_error');
}
function addEntryFailed() {
  $(document).triggerHandler('media_recording_error');
}
function addEntryComplete(entries) {
  $.mediaComment.lastAddAttemptId = null;
  $("#audio_record_holder_message,#video_record_holder_message").removeClass('saving');
  try {
    var userTitle = null;
    if(!$.isArray(entries)) {
      entries = [entries];
    }
    for(var idx = 0; idx < entries.length; idx++) {
      var entry = entries[idx];
      if($("#media_record_tabs").tabs('option', 'selected') == 0) {
        userTitle = $("#video_record_title,#audio_record_title").filter(":visible:first").val();
      } else if($("#media_record_tabs").tabs('option', 'selected') == 1) {
      }
      if(entry.entryType == 1 && $("#audio_record_option").hasClass('selected_option')) {
        entry.entryType = 5;
      }
      console.log([entry.entryId, entry.entryType, entry.entryName, userTitle]);
      $.mediaComment.entryAdded(entry.entryId, entry.entryType, entry.entryName, userTitle);
      $("#media_comment_dialog").dialog('close');
    }
  } catch(e) {
    console.log(e);
    alert("Entry failed to save.  Please try again.");
  }
}
