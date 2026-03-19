function escape_html(text){ 
  text = text.toString();
  
  return text.replace(/&/g, "&amp;"
      ).replace(/</g, "&lt;"
      ).replace(/>/g, "&gt;"
      ).replace(/"/g, "&quot;"
      ).replace(/'/g, "&#x27;"
    )
}