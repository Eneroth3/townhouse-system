function escape_html(text){
  //if (typeof text !== 'string' && !(text instanceof String)) {
  //  throw('"' + text + '" is not a string.')
  //}
  
  text = text.toString();
  
  return text.replace(/&/g, "&amp;"
      ).replace(/</g, "&lt;"
      ).replace(/>/g, "&gt;"
      ).replace(/"/g, "&quot;"
      ).replace(/'/g, "&#x27"
    )
}