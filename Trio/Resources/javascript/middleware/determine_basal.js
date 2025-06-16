function middleware(iob, currenttemp, glucose_status, profile, autosens, meal, reservoir, clock, pump_history, basalProfile, trio_custom_oref_variables_temp) {
    
    // modify anything
    // return any reason what has changed.

    const disableAcce = 0;
    const setTarget = 0;

    reason = "Nothing changed";

    var reasonAutoISF = "";
    var reasonTarget = "";

    const d = new Date();
    let currentHour = d.getHours();
    const currentBG = glucose_status.glucose;

    // disable acceISF during the night
    if (disableAcce == 1) {
        if (currentHour < 7 || currentHour > 22) {
             profile.enable_BG_acceleration = false;
             reasonAutoISF = "acceISF deactivated";
             reason = "";
            }
        }
    if (setTarget == 1) {
        if     (currentHour > 22 || currentHour < 7 && currentBG < 130) {
            profile.min_bg = 101;
            profile.max_bg = profile.min_bg;
            reasonTarget = ", TT set to: " + profile.min_bg;
            reason = "BG is: " + currentBG + ", ";
        };
    }
    reason = reason + reasonAutoISF + reasonTarget;

    // return any reason what has changed.
    return reason;
}

