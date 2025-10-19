"use strict";

module.exports = {
  extract_session_token,
};

function extract_session_token(req, context, ee, next) {
  try {
    const qr = String(context.vars.qr_text || "");
    const m = qr.match(/^ATTEND:(.+)$/);
    context.vars.session_token = m ? m[1] : "";
  } catch (_) {
    context.vars.session_token = "";
  }
  return next();
}

