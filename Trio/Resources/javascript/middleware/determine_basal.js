function middleware(iob, currenttemp, glucose_status, profile, autosens, meal, reservoir, clock, pump_history, preferences, basalProfile, oref2_variables) {
    
    // modify anything
    // return any reason what has changed.

    const currentBG = glucose_status.glucose;
    const trend = glucose_status.delta;
    const d = new Date();
    let currentHour = d.getHours();
    
    return "Nothing changed";

}
