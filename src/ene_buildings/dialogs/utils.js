function escape_html(text){ 
  text = text.toString();
  
  return text.replace(/&/g, "&amp;"
      ).replace(/</g, "&lt;"
      ).replace(/>/g, "&gt;"
      ).replace(/"/g, "&quot;"
      ).replace(/'/g, "&#x27;"
    )
}

// Similar to native encodeUriComponent() but also encodes !, ', (, ), and *.
// https://forums.sketchup.com/t/bug-webdialog-callback-has-trouble-handling-special-characters-even-when-escaped/26300/8
function fullUrlEncode(text) {
  return encodeURIComponent(text).replace(/[!'()*]/g, function(c) {
    return '%' + c.charCodeAt(0).toString(16);
  });
}

// Encode string before attaching as param to WebDialog's js to Ruby hack.
//
// window.location='skp:callback_name@' + encodeSkpParam(params);
//
// Corresponds to Ruby parse_params
function encodeSkpParam(param) {
  // SketchUp uses fucking eval with hardcoded single quotes to parse the value from JS.
  // Encode to get rid of closing ' character, preventing the string from breaking out and causing code injection.
  // Encode a second time as SketchUp implicitly decodes before running evaluating the string.
  // HACK: This breaks if SketchUp fixes the bug and makes `window.location='skp:` transfer the string without changing it.
  // If so, only encode once here. (Or not at all, but then also stop decoding in Ruby)
  return fullUrlEncode(fullUrlEncode(param));
}
