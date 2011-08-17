// TinyMCE-jQuery EditorBox plugin
// Called on a jQuery selector (should be a single object only)
// to initialize a TinyMCE editor box in the place of the 
// selected textarea: $("#edit").editorBox().  The textarea
// must have a unique id in order to function properly.
// editorBox():
// Initializes the object.  All other methods should
// only be called on an already-initialized box.
// editorBox('focus', [keepTrying])
//   Passes focus to the selected editor box.  Returns
//   true/false depending on whether the focus attempt was 
//   successful.  If the editor box has not completely initialized
//   yet, then the focus will fail.  If keepTrying
//   is defined and true, the method will keep trying until
//   the focus attempt succeeds.
// editorBox('destroy')
//   Removes the TinyMCE instance from the textarea.
// editorBox('toggle')
//   Toggles the TinyMCE instance.  Switches back and forth between
//   the textarea and the Tiny WYSIWYG.
// editorBox('get_code')
//   Returns the plaintext code contained in the textarea or WYSIGWYG.
// editorBox('set_code', code)
//   Sets the plaintext code content for the editor box.  Replaces ALL
//   content with the string value of code.
// editorBox('insert_code', code)
//   Inserts the string value of code at the current selection point.
// editorBox('create_link', options)
//   Creates an anchor link at the current selection point.  If anything
//   is selected, makes the selection a link, otherwise creates a link.
//   options.url is used for the href of the link, and options.title
//   will be the body of the link if no text is currently selected.
(function( $ ) {
  
  var enableBookmarking = $("body").hasClass('ie');
  $(document).ready(function() {
    enableBookmarking = $("body").hasClass('ie');
  });
  function EditorBoxList() {
    this._textareas = {};
    this._editors = {};
    this._editor_boxes = {};
  };

  $.extend(EditorBoxList.prototype, {
    _addEditorBox: function(id, box) {
      this._editor_boxes[id] = box;
      this._editors[id] = tinyMCE.get(id);
      this._textareas[id] = $("textarea#" + id);
    },
    _removeEditorBox: function(id) {
      delete this._editor_boxes[id];
      delete this._editors[id];
      delete this._textareas[id];
    },
    _getTextArea: function(id) {
      if(!this._textareas[id]) {
        this._textareas[id] = $("textarea#" + id);
      }
      return this._textareas[id];
    },
    _getEditor: function(id) {
      if(!this._editors[id]) {
        this._editors[id] = tinyMCE.get(id);
      }
      return this._editors[id];
    },
    _getEditorBox: function(id) {
      return this._editor_boxes[id];
    }
  });

  var $instructureEditorBoxList = new EditorBoxList();

  function fillViewportWithEditor(editorID, elementToLeaveInViewport){
  
    var $iframe = $("#"+editorID+"_ifr");
    if ($iframe.length) {
      var newHeight = $(window).height() - ($iframe.offset().top + elementToLeaveInViewport.height() + 1);
      $iframe.height(newHeight);
    }
    $("#"+editorID+"_tbl").css('height', '');
  }

  function EditorBox(id, search_url, submit_url, content_url, options) {
    options = $.extend({}, options);
    if (options.fullHeight) {
      $(window).resize(function(){
        fillViewportWithEditor(id, options.elementToLeaveInViewport);
      }).triggerHandler('resize');
    }
    var $dom = $("#" + id);
    $dom.data('enable_bookmarking', enableBookmarking);
    var width = $("#" + id).width();
    if(width == 0) {
      width = $("#" + id).closest(":visible").width();
    }
    var instructure_buttons = ",instructure_embed,instructure_equation";
    if(INST && INST.allowMediaComments) {
      instructure_buttons = instructure_buttons + ",instructure_record";
    }
    var equella_button = INST && INST.equellaEnabled ? ",instructure_equella" : "";
    instructure_buttons = instructure_buttons + equella_button;
  
    var buttons1 = "bold,italic,underline,forecolor,backcolor,removeformat,sepleft,separator,justifyleft,justifycenter,justifyright,sepleft,separator,bullist,outdent,indent,numlist,sepleft,separator,table,instructure_links,unlink" + instructure_buttons + ",|,fontsizeselect,formatselect";
    var buttons2 = "";
    var buttons3 = "";
    if(width < 460 && width > 0) {
      buttons1 = "bold,italic,underline,forecolor,backcolor,removeformat,sepleft,separator,justifyleft,justifycenter,justifyright";
      buttons2 = "outdent,indent,bullist,numlist,sepleft,separator,table,instructure_links,unlink" + instructure_buttons;
      buttons3 = "fontsizeselect,formatselect";
    } else if(width < 860) {
      buttons1 = "bold,italic,underline,forecolor,backcolor,removeformat,sepleft,separator,justifyleft,justifycenter,justifyright,sepleft,separator,outdent,indent,bullist,numlist";
      buttons2 = "table,instructure_links,unlink" + instructure_buttons + ",|,fontsizeselect,formatselect";
    } else {
    }
    var ckStyle = true;
    var editor_css = "/javascripts/tinymce/jscripts/tiny_mce/themes/advanced/skins/default/ui.css";
    if(ckStyle) {
      editor_css += ",/stylesheets/compiled/tiny_like_ck.css";
    }
    tinyMCE.init({
      mode : "exact",
      elements: id,
      theme : "advanced",
      plugins: "contextmenu,instructure_links,instructure_embed,instructure_equation,instructure_record,instructure_equella,media,paste,table,inlinepopups",
      dialog_type: 'modal',
      relative_urls: false,
      remove_script_host: true,
      theme_advanced_buttons1: buttons1,
      theme_advanced_toolbar_location : "top",
      theme_advanced_buttons2: buttons2,
      theme_advanced_buttons3: buttons3,
    
      theme_advanced_resize_horizontal : false,
      theme_advanced_resizing : true,
      theme_advanced_fonts : "Andale Mono=andale mono,times;Arial=arial,helvetica,sans-serif;Arial Black=arial black,avant garde;Book Antiqua=book antiqua,palatino;Comic Sans MS=comic sans ms,sans-serif;Courier New=courier new,courier;Georgia=georgia,palatino;Helvetica=helvetica;Impact=impact,chicago;Myriad=\"Myriad Pro\",Myriad,Arial,sans-serif;Symbol=symbol;Tahoma=tahoma,arial,helvetica,sans-serif;Terminal=terminal,monaco;Times New Roman=times new roman,times;Trebuchet MS=trebuchet ms,geneva;Verdana=verdana,geneva;Webdings=webdings;Wingdings=wingdings,zapf dingbats;",
      theme_advanced_blockformats : "p,h2,h3,h4,pre",
      theme_advanced_more_colors: false,
      extended_valid_elements : "iframe[src|width|height|name|align|style|class]",
      content_css: "/stylesheets/compiled/instructure_style.css,/stylesheets/compiled/tinymce.editor_box.css",
      editor_css:editor_css,
      handle_event_callback: function(e) {
        if(e.type.indexOf('keydown') === 0 || e.type.indexOf('keypress') === 0) {
          if(e.keyCode === 9) {
            if(e.shiftKey) {
              e.preventDefault();
              var $ed = $("#" + id);
              var $items = $ed.closest("form,#main").find(":tabbable,#" + id);
              idx = $items.index($ed);
              if($ed.filter(":visible").length > 0) {
                $($items.eq(idx - 1)).focus();
              } else {
                $($items.eq(idx + 1)).focus();
              }
            }
          } else {
            $("#" + id).triggerHandler(e.type, $.event.fix(e));
          }
        }
      },
      onchange_callback: function(e) {
        $("#" + id).trigger('change');
      },
      setup : function(ed) {
        var focus = function() {
          $(document).triggerHandler('editor_box_focus', $("#" + ed.editorId));
        };
        ed.onClick.add(focus);
        ed.onKeyPress.add(focus);
        ed.onActivate.add(focus);
        ed.onEvent.add(function() {
          if(enableBookmarking && ed.selection) {
            $dom.data('last_bookmark', ed.selection.getBookmark(1));
          }
        });
        ed.onInit.add(function(){
          $(window).triggerHandler("resize");
        
          // this is a hack so that when you drag an image from the wikiSidebar to the editor that it doesn't 
          // try to embed the thumbnail but rather the full size version of the image.
          // so basically, to document why and how this works: in wiki_sidebar.js we add the 
          // _mce_src="http://path/to/the/fullsize/image" to the images who's src="path/to/thumbnail/of/image/" 
          // what this does is check to see if some DOM node that  got inserted into the editor has the attribute _mce_src
          // and if it does, use that instead.
          $(ed.contentDocument).bind("DOMNodeInserted", function(e){
            var target = e.target, 
                mceSrc;
            if (target.nodeType === 1 && target.nodeName === 'IMG'  && (mceSrc = $(target).attr('_mce_src')) ) {
              $(target).attr('src', tinyMCE.activeEditor.documentBaseURI.toAbsolute(mceSrc));
            }
          });
        
          if(ckStyle) {
            $("#" + ed.editorId + "_tbl").find("td.mceToolbar span.mceSeparator").parent().each(function() {
              $(this)
                .after("<td class='mceSeparatorLeft'><span/></td>")
                .after("<td class='mceSeparatorMiddle'><span/></td>")
                .after("<td class='mceSeparatorRight'><span/></td>")
                .remove();
            });
          }
          if (!options.unresizable) {
            var iframe = $("#"+id+"_ifr"),
                table = $("#"+id+"_tbl"),
                iframeOffsetTop,
                keepMeFromMousingOverIframe,
                minHeight = (options.minHeight || 200),
                helper = $('<div class="editor_box_resizer" unselectable="on"><div class="ui-icon ui-icon-grip-diagonal-se" unselectable="on"></div></div>')
            .appendTo(iframe.parent())
            .draggable({
              axis: 'y',
              containment: [0, iframe.offset().top + minHeight , 9999999, 9999999],
              start: function(){
                iframeOffsetTop = iframe.offset().top;
                // I dont know if absolutely necessary but, do this just in case the top offset of the iframe got changed
                // between initializion and when we started dragging
                // (ex: some extra content got added before this element so it caused it to move down)
                helper.draggable('option', 'containment', [0, iframeOffsetTop + minHeight , 9999999, 9999999]);
                table.css('height', '');
                keepMeFromMousingOverIframe = $('<div style="position: absolute; width: 100%; height: 100%; top: 0; left: 0;"></div>').appendTo('body');
              },
              drag: function(event, ui) {
                iframe.height(ui.offset.top - iframeOffsetTop);
                helper.css('top', '');
              },
              stop: function(event, ui){
                keepMeFromMousingOverIframe.remove();
                iframe.height(ui.offset.top - iframeOffsetTop);
                table.css('height', '');
                helper.css('top', '');
              }
            });
          }
        });
      }
    });


    this._textarea = $("#" + id);//$("#" + id);
    this._editor = null;
    this._id = id;
    this._searchURL = search_url;
    this._submitURL = submit_url;
    this._contentURL = content_url;
    $instructureEditorBoxList._addEditorBox(id, this);
    $("#" + id).bind('blur change', function() {
      if($instructureEditorBoxList._getEditor(id) && $instructureEditorBoxList._getEditor(id).isHidden()) {
        $(this).editorBox('set_code', $instructureEditorBoxList._getTextArea(id).val());
      }
    });  
  }

  var fieldSelection = {

    getSelection: function() {

      var e = this.jquery ? this[0] : this;

      return (

        /* mozilla / dom 3.0 */
        ('selectionStart' in e && function() {
          var l = e.selectionEnd - e.selectionStart;
          return { start: e.selectionStart, end: e.selectionEnd, length: l, text: e.value.substr(e.selectionStart, l) };
        }) ||

        /* exploder */
        (document.selection && function() {

          e.focus();

          var r = document.selection.createRange();
          if (r == null) {
            return { start: 0, end: e.value.length, length: 0 };
          }

          var re = e.createTextRange();
          var rc = re.duplicate();
          re.moveToBookmark(r.getBookmark());
          rc.setEndPoint('EndToStart', re);

          return { start: rc.text.length, end: rc.text.length + r.text.length, length: r.text.length, text: r.text };
        }) ||

        /* browser not supported */
        function() {
          return { start: 0, end: e.value.length, length: 0 };
        }

      )();

    },

    replaceSelection: function() {

      var e = this.jquery ? this[0] : this;
      var text = arguments[0] || '';

      return (

        /* mozilla / dom 3.0 */
        ('selectionStart' in e && function() {
          e.value = e.value.substr(0, e.selectionStart) + text + e.value.substr(e.selectionEnd, e.value.length);
          return this;
        }) ||

        /* exploder */
        (document.selection && function() {
          e.focus();
          document.selection.createRange().text = text;
          return this;
        }) ||

        /* browser not supported */
        function() {
          e.value += text;
          return this;
        }

      )();

    }

  };

  jQuery.each(fieldSelection, function(i) { jQuery.fn[i] = this; });


// --------------------------------------------------------------------


  var editorBoxIdCounter = 1;
  
  $.fn.editorBox = function(options, more_options) {
    if(this.length > 1) {
      return this.each(function() {
        $(this).editorBox(options, more_options);
      });
    }
    var id = this.attr('id');
    if(typeof(options) == "string" && options != "create") {
      if(options == "get_code") {
        return this._getContentCode(more_options);
      } else if(options == "set_code") {
        this._setContentCode(more_options);
      } else if(options == "insert_code") {
        this._insertHTML(more_options);
      } else if(options == "selection_offset") {
        return this._getSelectionOffset();
      } else if(options == "selection_link") {
        return this._getSelectionLink();
      } else if(options == "create_link") {
        this._linkSelection(more_options);
      } else if(options == "focus") {
        return this._editorFocus(more_options);
      } else if(options == "toggle") {
        this._toggleView();
      } else if(options == "execute") {
        var arr = [];
        for(var idx = 1; idx < arguments.length; idx++) {
          arr.push(arguments[idx]);
        }
        return $.fn._execCommand.apply(this, arr);
      } else if(options == "destroy") {
        this._removeEditor(more_options);
      }
      return this;
    }
    this.data('rich_text', true);
    if(!id) {
      id = 'editor_box_unique_id_' + editorBoxIdCounter++;
      this.attr('id', id);
    }
    if($instructureEditorBoxList._getEditor(id)) {
      this._setContentCode(this.val());
      return this;
    }
    var search_url = "";
    if(options && options.search_url) {
      search_url = options.search_url;
    }
    var box = new EditorBox(id, search_url, "", "", options);
    return this;
  };
  
  $.fn._execCommand = function() {
    var id = $(this).attr('id');
    var editor = $instructureEditorBoxList._getEditor(id);
    if(editor && editor.execCommand) {
      editor.execCommand.apply(editor, arguments);
    }
  };
  
  $.fn._justGetCode = function() {
    var id = this.attr('id');
    var content = "";
    try {
      if($instructureEditorBoxList._getEditor(id).isHidden()) {
        content = $instructureEditorBoxList._getTextArea(id).val();
      } else {
        content = $instructureEditorBoxList._getEditor(id).getContent();
      }
    } catch(e) {
      if(tinyMCE && tinyMCE.getInstanceById(id)) {
        content = tinyMCE.getInstanceById(id).getContent();
      } else {
        content = this.val() || "";
      }
    }
    return content;
  };
  
  $.fn._getContentCode = function(update) {
    if(update == true) {
      var content = this._justGetCode(); //""
      this._setContentCode(content);
    }
    return this._justGetCode();
  };
  
  $.fn._getSearchURL = function() {
    return $instructureEditorBoxList._getEditorBox(this.attr('id'))._searchURL;
  };
  
  $.fn._getSubmitURL = function() {
    return $instructureEditorBoxList._getEditorBox(this.attr('id'))._submitURL;
  };
   
  $.fn._getContentURL = function() {
    return $instructureEditorBoxList._getEditorBox(this.attr('id'))._contentURL;
  };
  
  $.fn._getSelectionOffset = function() {
    var id = this.attr('id');
    var box = $instructureEditorBoxList._getEditor(id).getContainer();
    var boxOffset = $(box).find('iframe').offset();
    var node = $instructureEditorBoxList._getEditor(id).selection.getNode();
    var nodeOffset = $(node).offset();
    var scrollTop = $(box).scrollTop();
    var offset = {
      left: boxOffset.left + nodeOffset.left + 10,
      top: boxOffset.top + nodeOffset.top + 10 - scrollTop
    };
    return offset;
  };
  
  $.fn._getSelectionNode = function() {
    var id = this.attr('id');
    var box = $instructureEditorBoxList._getEditor(id).getContainer();
    var node = $instructureEditorBoxList._getEditor(id).selection.getNode();
    return node;
  };
  
  $.fn._getSelectionLink = function() {
    var id = this.attr('id');
    var node = tinyMCE.get(id).selection.getNode();
    while(node.nodeName != 'A' && node.nodeName != 'BODY' && node.parentNode) {
      node = node.parentNode;
    }
    if(node.nodeName == 'A') {
      var href = $(node).attr('href');
      var title = $(node).attr('title');
      if(!title || title == '') {
        title = href;
      }
      var result = {
        url: href,
        title: title
      };
      return result;
    }
    return null;
  };
  
  $.fn._toggleView = function() {
    var id = this.attr('id');
    this._setContentCode(this._getContentCode());
    tinyMCE.execCommand('mceToggleEditor', false, id);
  };
  
  $.fn._removeEditor = function() {
    var id = this.attr('id');
    this.data('rich_text', false);
    if(tinyMCE && tinyMCE.execCommand) {
      tinyMCE.execCommand('mceRemoveControl', false, id);
      $instructureEditorBoxList._removeEditorBox(id);
    }
  };
  
  $.fn._setContentCode = function(val) {
    var id = this.attr('id');
    $instructureEditorBoxList._getTextArea(id).val(val);
    if(tinyMCE.get(id) && $.isFunction(tinyMCE.get(id).execCommand)) {
      tinyMCE.get(id).execCommand('mceSetContent', false, val);
    }
  };
  
  $.fn._insertHTML = function(html) {
    var id = this.attr('id');
    if($instructureEditorBoxList._getEditor(id).isHidden()) {
      this.replaceSelection(html);
    } else {
      tinyMCE.get(id).execCommand('mceInsertContent', false, html);
    }
  };
  
  $.fn._editorFocus = function(keepTrying) {
    var $element = this,
        id = $element.attr('id'),
        editor = $instructureEditorBoxList._getEditor(id);
    if (keepTrying && (!editor || !editor.dom.doc.hasFocus())) {
      setTimeout(function(){
        $element.editorBox('focus', true);
      }, 50);
    }
    if(!editor ) {
      return false; 
    }
    if($instructureEditorBoxList._getEditor(id).isHidden()) {
      $instructureEditorBoxList._getTextArea(id).focus().select();
    } else {
      tinyMCE.execCommand('mceFocus', false, id);
    }
    return true;
  };
  
  $.fn._linkSelection = function(options) {
    if(typeof(options) == "string") {
      options = {url: options};
    }
    var title = options.title;
    var url = options.url || "";
    if(url.match(/@/) && !url.match(/\//) && !url.match(/^mailto:/)) {
      url = "mailto:" + url;
    } else if(!url.match(/^\w+:\/\//) && !url.match(/^mailto:/) && !url.match(/^\//)) {
      url = "http://" + url;
    }
    var classes = options.classes || "";
    var id = $(this).attr('id');
    if(url.indexOf("@") != -1) {
      options.file = false;
      options.image = false;
      if(url.indexOf("mailto:") != 0) {
        url = "mailto:" + url;
      }
    } else if (url.indexOf("/") == -1) {
      title = url;
      url = url.replace(/\s/g, "");
      url = location.href + url;
    }
    if(options.file) {
      classes += "instructure_file_link ";
    }
    if(options.scribdable) {
      classes += "instructure_scribd_file ";
    }
    var link_id = '';
    if(options.kaltura_entry_id && options.kaltura_media_type) {
      link_id = "media_comment_" + options.kaltura_entry_id;
      if(options.kaltura_media_type == 'video') {
        classes += "instructure_video_link ";
      } else {
        classes += "instructure_audio_link ";
      }
    }
    if(options.image) {
      classes += "instructure_image_thumbnail ";
    }
    classes = $.uniq(classes.split(/\s+/)).join(" ")
    var selectionText = "";
    if(enableBookmarking && this.data('last_bookmark')) {
      tinyMCE.get(id).selection.moveToBookmark(this.data('last_bookmark'));
    }
    var selection = tinyMCE.get(id).selection;
    var anchor = selection.getNode();
    while(anchor.nodeName != 'A' && anchor.nodeName != 'BODY' && anchor.parentNode) {
      anchor = anchor.parentNode;
    }
    if(anchor.nodeName != 'A') { anchor = null; }
    
    var selectedContent = selection.getContent();
    if($instructureEditorBoxList._getEditor(id).isHidden()) {
      selectionText = title || "Link";
      var $div = $("<div><a/></div>");
      $div.find("a")
        [link_id ? 'attr' : 'removeAttr']('id', link_id)
        .attr('title', title)
        .attr('href', url)
        [classes ? 'attr' : 'removeAttr']('class', classes)
        .text(selectionText);
      var link_html = $div.html();
      $(this).replaceSelection(link_html);
    } else if(!selectedContent || selectedContent == "") {
      if(anchor) {
        $(anchor).attr('href', url).attr('_mce_href', url).attr('title', title || '').attr('id', link_id).attr('class', classes);
      } else {
        selectionText = title || "Link";
        var $div = $("<div/>");
        $div.append($("<a/>", {id: link_id, title: title, href: url, 'class': classes}).text(selectionText));
        tinyMCE.get(id).execCommand('mceInsertContent', false, $div.html());
      }
    } else {
      tinyMCE.get(id).execCommand('mceInsertLink', false, {title: (title || ''), href: url, 'class': classes, 'id': link_id});
    }

    var ed = tinyMCE.get(id);
    var e = ed.selection.getNode();
    if(e.nodeName != 'A') {
      e = $(e).children("a:last")[0];
    }
    if(e) {
      var nodeOffset = {top: e.offsetTop, left: e.offsetLeft};
      var n = e;
      // There's a weird bug here that I can't figure out.  If the editor box is scrolled
      // down and the parent window is scrolled down, it gives different value for the offset
      // (nodeOffset) than if only the editor window is scrolled down.  You scroll down
      // one pixel and it changes the offset by like 60.
      // This is the fix.
      while((n = n.offsetParent) && n.tagName != 'BODY') {
        nodeOffset.top = nodeOffset.top + n.offsetTop || 0;
        nodeOffset.left = nodeOffset.left + n.offsetLeft || 0;
      }
      var box = ed.getContainer();
      var boxOffset = $(box).find('iframe').offset();
      var frameTop = $(ed.dom.doc).find("html").scrollTop() || $(ed.dom.doc).find("body").scrollTop();
      var offset = {
        left: boxOffset.left + nodeOffset.left,
        top: boxOffset.top + nodeOffset.top - frameTop
      };
      $(e).indicate({offset: offset, singleFlash: true, scroll: true, container: $(box).find('iframe')});
    }
  };
  
})(jQuery);

// This Nifty Little Effect is for when you add a link the the TinyMCE editor it looks like it is physically transfered to the editor.  
// unfortunately it doesnt work yet so dont use it.  I might go back to it sometime if we want it. -RS
// 
// (function($) {
// $.effects.transferToEditor = function(o) {
// 
//  return this.queue(function() {
//    // Create element
//    var el = $(this);
//    var node = $(o.options.editor)._getSelectionNode();
//    
//    // Set options
//    var mode = $.effects.setMode(el, o.options.mode || 'effect'); // Set Mode
//    var target = $(node); // Find Target
//    var position = el.offset();
//    var transfer = $('<div class="ui-effects-transfer"></div>').appendTo(document.body);
//    if(o.options.className) transfer.addClass(o.options.className);
//    
//    // Set target css
//    transfer.addClass(o.options.className);
//    transfer.css({
//      top: position.top,
//      left: position.left,
//      height: el.outerHeight() - parseInt(transfer.css('borderTopWidth')) - parseInt(transfer.css('borderBottomWidth')),
//      width: el.outerWidth() - parseInt(transfer.css('borderLeftWidth')) - parseInt(transfer.css('borderRightWidth')),
//      position: 'absolute'
//    });
//    
//    // Animation
//    position = $(o.options.editor)._getSelectionOffset();
//    animation = {
//      top: position.top,
//      left: position.left,
//      height: target.outerHeight() - parseInt(transfer.css('borderTopWidth')) - parseInt(transfer.css('borderBottomWidth')),
//      width: target.outerWidth() - parseInt(transfer.css('borderLeftWidth')) - parseInt(transfer.css('borderRightWidth'))
//    };
//    
//    // Animate
//    transfer.animate(animation, o.duration, o.options.easing, function() {
//      transfer.remove(); // Remove div
//      if(o.callback) o.callback.apply(el[0], arguments); // Callback
//      el.dequeue();
//    }); 
//    
//  });
//  
// };
// 
// })(jQuery);
// ;
