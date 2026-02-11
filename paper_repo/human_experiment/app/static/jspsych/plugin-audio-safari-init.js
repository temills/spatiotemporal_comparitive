/**
 * jspsych-audio-safari-init
 * Etienne Gaudrain
 *
 * Safari is the new Internet Explorer and does everything differently from others
 * for better, and mostly for worse. Here is a plugin to display a screen for the user to click on
 * before starting the experiment to unlock the audio context, if we are dealing with Safari.
 *
 **/

var jsPsychAudioSafariInit = (function (jspsych) {
    'use strict';

    //jsPsych.pluginAPI.registerPreload('audio-safari-init', 'stimulus', 'audio');

    const info = {
        name: 'audio-safari-init',
        description: '',
        parameters: {
            prompt: {
                type: jspsych.ParameterType.STRING,
                pretty_name: 'Prompt',
                default: "Please make sure your device is in landscape orientation. Then, click on the screen to start the task!",
                description: 'The prompt asking the user to click on the screen.'
            }
        }
    }

    class AudioSafariInitPlugin {
        constructor(jsPsych) {
            this.jsPsych = jsPsych;
        }
        trial(display_element, trial, on_load) {

            function update_prompt() {
                
                if (isTablet()) {
                    display_element.innerHTML = "Please make sure your device is in landscape orientation. Then, click on the screen to start the task!"
                } else {
                    display_element.innerHTML = "Please use a <b>tablet</b> to complete this task"
                }
                
            }

            update_prompt()
            document.addEventListener('touchstart', init_audio);
            document.addEventListener('click', init_audio);


            function init_audio(){
                // first check iphone
                update_prompt()
                if (isTablet() && checkOrientation()) {
                    jsPsych.pluginAPI.audioContext();
                    end_trial();
                }
            }

            function isTablet() {
                return true; // for now allow non-tablets
                const userAgent = navigator.userAgent.toLowerCase();
                const isIPad = /ipad/.test(userAgent) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
                const isAndroidTablet = /android/.test(userAgent) && !/mobile/.test(userAgent);
                return (isIPad || isAndroidTablet)
            }
            
            function isSmartphone() {
                const userAgent = navigator.userAgent.toLowerCase();
                return /iphone|ipod|android.*mobile/.test(userAgent);
            }

            function checkTablet() {
                if (isTablet()) {
                    return true
                } else {
                    return false
                }
                // } else if (isSmartphone()) {
                //     console.log("Smartphone detected");
                // } else {
                //     console.log("Neither a smartphone nor a tablet");
                // }
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

                document.removeEventListener('touchstart', init_audio);
                document.removeEventListener('click', init_audio);

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
    AudioSafariInitPlugin.info = info;

    return AudioSafariInitPlugin;
      
})(jsPsychModule);
      