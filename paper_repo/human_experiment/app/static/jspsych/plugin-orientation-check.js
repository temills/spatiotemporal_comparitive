/**
 * jspsych-audio-safari-init
 * Etienne Gaudrain
 *
 * Safari is the new Internet Explorer and does everything differently from others
 * for better, and mostly for worse. Here is a plugin to display a screen for the user to click on
 * before starting the experiment to unlock the audio context, if we are dealing with Safari.
 *
 **/

var jsPsychOrientationCheck = (function (jspsych) {
    'use strict';

    //jsPsych.pluginAPI.registerPreload('audio-safari-init', 'stimulus', 'audio');

    const info = {
        name: 'orientation-check',
        description: '',
        parameters: {
            prompt: {
                type: jspsych.ParameterType.STRING,
                pretty_name: 'Prompt',
                default: "Please make sure your device is in landscape orientation. Then, click on the screen to continue the task!",
                description: 'The prompt asking the user to click on the screen.'
            }
        }
    }

    class OrientationCheckPlugin {
        constructor(jsPsych) {
            this.jsPsych = jsPsych;
        }
        trial(display_element, trial, on_load) {

            // Ideally, we would want to be able to detect this on feature basis rather than using userAgents,
            // but Safari just doesn't count clicks not directly aimed at starting sounds, while other browsers do.

            display_element.innerHTML = trial.prompt;
            document.addEventListener('touchstart', init_end);
            document.addEventListener('click', init_end);

            function init_end(){
                if (checkOrientation()) {
                    end_trial();
                }
            }
            function checkOrientation() {
                if (window.matchMedia("(orientation: portrait)").matches) {
                  // Portrait orientation
                  return false
                } else {
                  // Landscape orientation
                  return true
                }
            }

            // function to end trial when it is time
            function end_trial() {

                document.removeEventListener('touchstart', init_end);
                document.removeEventListener('click', init_end);

                // kill any remaining setTimeout handlers
                jsPsych.pluginAPI.clearAllTimeouts();

                // kill keyboard listeners
                jsPsych.pluginAPI.cancelAllKeyboardResponses();

                // clear the display
                display_element.innerHTML = '';

                // move on to the next trial
                jsPsych.finishTrial();
            }


        };
    }
    OrientationCheckPlugin.info = info;

    return OrientationCheckPlugin;
      
})(jsPsychModule);
      