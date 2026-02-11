var jsPsychGreatJob = (function (jspsych) {
    'use strict';
  
    const info = {
        name: "great-job",
        parameters: {
            /** Array of the video file(s) to play. Video can be provided in multiple file formats for better cross-browser support. */
            stimulus: {
                type: jspsych.ParameterType.VIDEO,
                pretty_name: "Video",
                default: undefined,
                array: true,
            },
            audio_stimulus: {
                type: jspsych.ParameterType.AUDIO,
                pretty_name: "Audio",
                default: undefined,
                array: true,
            },
            /** Array containing the label(s) for the button(s). */
            choices: {
                type: jspsych.ParameterType.STRING,
                pretty_name: "Choices",
                default: undefined,
                array: true,
            },
            /** The HTML for creating button. Can create own style. Use the "%choice%" string to indicate where the label from the choices parameter should be inserted. */
            button_html: {
                type: jspsych.ParameterType.HTML_STRING,
                pretty_name: "Button HTML",
                default: '<button class="jspsych-btn">%choice%</button>',
                array: true,
            },
            /** Any content here will be displayed below the buttons. */
            prompt: {
                type: jspsych.ParameterType.HTML_STRING,
                pretty_name: "Prompt",
                default: null,
            },
            /** The width of the video in pixels. */
            width: {
                type: jspsych.ParameterType.INT,
                pretty_name: "Width",
                default: "",
            },
            total_stars: {
                type: jspsych.ParameterType.INT,
                pretty_name: "total stars",
                default: 7,
            },
            star_idx: {
                type: jspsych.ParameterType.INT,
                pretty_name: "star idx",
                default: -1,
            },
            /** The height of the video display in pixels. */
            height: {
                type: jspsych.ParameterType.INT,
                pretty_name: "Height",
                default: "",
            },
            /** If true, the video will begin playing as soon as it has loaded. */
            autoplay: {
                type: jspsych.ParameterType.BOOL,
                pretty_name: "Autoplay",
                default: true,
            },
            /** If true, the subject will be able to pause the video or move the playback to any point in the video. */
            controls: {
                type: jspsych.ParameterType.BOOL,
                pretty_name: "Controls",
                default: false,
            },
            /** Time to start the clip. If null (default), video will start at the beginning of the file. */
            start: {
                type: jspsych.ParameterType.FLOAT,
                pretty_name: "Start",
                default: null,
            },
            /** Time to stop the clip. If null (default), video will stop at the end of the file. */
            stop: {
                type: jspsych.ParameterType.FLOAT,
                pretty_name: "Stop",
                default: null,
            },
            /** The playback rate of the video. 1 is normal, <1 is slower, >1 is faster. */
            rate: {
                type: jspsych.ParameterType.FLOAT,
                pretty_name: "Rate",
                default: 1,
            },
            /** If true, the trial will end immediately after the video finishes playing. */
            trial_ends_after_video: {
                type: jspsych.ParameterType.BOOL,
                pretty_name: "End trial after video finishes",
                default: false,
            },
            /** How long to show trial before it ends. */
            trial_duration: {
                type: jspsych.ParameterType.INT,
                pretty_name: "Trial duration",
                default: null,
            },
            /** The vertical margin of the button. */
            margin_vertical: {
                type: jspsych.ParameterType.STRING,
                pretty_name: "Margin vertical",
                default: "0px",
            },
            /** The horizontal margin of the button. */
            margin_horizontal: {
                type: jspsych.ParameterType.STRING,
                pretty_name: "Margin horizontal",
                default: "8px",
            },
            /** If true, the trial will end when subject makes a response. */
            response_ends_trial: {
                type: jspsych.ParameterType.BOOL,
                pretty_name: "Response ends trial",
                default: true,
            },
            /** If true, then responses are allowed while the video is playing. If false, then the video must finish playing before a response is accepted. */
            response_allowed_while_playing: {
                type: jspsych.ParameterType.BOOL,
                pretty_name: "Response allowed while playing",
                default: true,
            },
        },
    };
    /**
     * **great-job-response**
     *
     * jsPsych plugin for playing a video file and getting a button response
     *
     * @author Josh de Leeuw
     * @see {@link https://www.jspsych.org/plugins/jspsych-video-button-response/ video-button-response plugin documentation on jspsych.org}
     */
    class GreatJobPlugin {
        constructor(jsPsych) {
            this.jsPsych = jsPsych;
        }
        trial(display_element, trial) {
            if (!Array.isArray(trial.stimulus)) {
                throw new Error(`
          The stimulus property for the video-button-response plugin must be an array
          of files. See https://www.jspsych.org/latest/plugins/video-button-response/#parameters
        `);
            }


            var data = []
            function start_audio() {
                data[1].play()
            }
            var loaded = 0;
            function handleDataLoad() {
              loaded++;
              // Check if all images have finished loading
              console.log(loaded)
              if (loaded === 2) {
                  init_html()
              }
            }
            function LoadData() {
                var image = new Image();
                image.src = trial.stimulus[0];
                data.push(image);
                image.onload = handleDataLoad;

                var audio = new Audio()
                audio.src = trial.audio_stimulus[0]
                console.log(trial.audio_stimulus[0])
                data.push(audio)
                audio.addEventListener('canplaythrough', function() { 
                    handleDataLoad();
                 }, false);

            }
    
            var star_colors = ["#F09EA7",
            "#F6CA94",
            "#FAFABE",
            "#C1EBC0",
            "#C7CAFF",
            "#CDABEB",
            "#F6C2F3"]

            var stars = ""

            // Fill a random star with the "active" class
            function fillStar(i) {
                if (i>=0) {
                    stars[i-1].classList.add("active");
                    stars[i-1].style.backgroundColor = star_colors[i-1]
                }
            }
    
            function init_html() {
                var video_html = "<div>";
                var file_name = trial.stimulus[0];
                video_html += '<div><img src="' + data[0].src + '" style="width:700px;"></div>'
                video_html += "</div>";
                
                if (trial.prompt !== null) {
                  video_html += trial.prompt;
                }
                // add stars
                video_html += '<div id="stars-container">'
                for(var i=1; i<=trial.total_stars;i++) {
                if (i < trial.star_idx) {
                    video_html += '<span class="star active" data-index="' + i + '" style="background-color: ' + star_colors[i-1] + '"></span>'
                } else {
                    video_html += '<span class="star" data-index="' + i + '"></span>'
                }
                }
                video_html += '</div>'
    
              //display buttons
              var buttons = [];
              if (Array.isArray(trial.button_html)) {
                  if (trial.button_html.length == trial.choices.length) {
                      buttons = trial.button_html;
                  }
                  else {
                      console.error("Error in video-button-response plugin. The length of the button_html array does not equal the length of the choices array");
                  }
                }
                else {
                    for (var i = 0; i < trial.choices.length; i++) {
                        buttons.push(trial.button_html);
                    }
                }
                video_html += '<div id="jspsych-video-button-response-btngroup">';
                for (var i = 0; i < trial.choices.length; i++) {
                    var str = buttons[i].replace(/%choice%/g, trial.choices[i]);
                    video_html +=
                        '<div class="jspsych-video-button-response-button" style="cursor: pointer; display: inline-block; margin:' +
                            trial.margin_vertical +
                            " " +
                            trial.margin_horizontal +
                            '" id="jspsych-video-button-response-button-' +
                            i +
                            '" data-choice="' +
                            i +
                            '">' +
                            str +
                            "</div>";
                }
                video_html += "</div>";
                display_element.innerHTML = video_html;
                setTimeout(() => {
                    start_audio() 
                    stars = document.querySelectorAll(".star");
                  }, 500);
                  setTimeout(() => {
                    fillStar(trial.star_idx)
                    enable_buttons()
                  }, 600);
            }

            setTimeout(() => {
                LoadData()
              }, 1000);
            var start_time = performance.now();

            // store response
            var response = {
                rt: null,
                button: null,
            };
            // function to end trial when it is time
            const end_trial = () => {
                // kill any remaining setTimeout handlers
                this.jsPsych.pluginAPI.clearAllTimeouts();
                // gather the data to store for the trial
                var trial_data = {
                    rt: response.rt,
                    stimulus: trial.stimulus,
                    response: response.button,
                };
                // clear the display
                display_element.innerHTML = "";
                // move on to the next trial
                this.jsPsych.finishTrial(trial_data);
            };
            // function to handle responses by the subject
            function after_response(choice) {
                // measure rt
                var end_time = performance.now();
                var rt = Math.round(end_time - start_time);
                response.button = parseInt(choice);
                response.rt = rt;
                // after a valid response, the stimulus will have the CSS class 'responded'
                // which can be used to provide visual feedback that a response was recorded
                // disable all the buttons after a response
                disable_buttons();
                if (trial.response_ends_trial) {
                    end_trial();
                }
            }
            function button_response(e) {
                var choice = e.currentTarget.getAttribute("data-choice"); // don't use dataset for jsdom compatibility
                after_response(choice);
            }
            function disable_buttons() {
                var btns = document.querySelectorAll(".jspsych-video-button-response-button");
                for (var i = 0; i < btns.length; i++) {
                    var btn_el = btns[i].querySelector("button");
                    if (btn_el) {
                        btn_el.disabled = true;
                    }
                    btns[i].removeEventListener("click", button_response);
                }
            }
            function enable_buttons() {
                var btns = document.querySelectorAll(".jspsych-video-button-response-button");
                for (var i = 0; i < btns.length; i++) {
                    var btn_el = btns[i].querySelector("button");
                    if (btn_el) {
                        btn_el.disabled = false;
                    }
                    btns[i].addEventListener("click", button_response);
                }
            }
            // end trial if time limit is set
            if (trial.trial_duration !== null) {
                this.jsPsych.pluginAPI.setTimeout(end_trial, trial.trial_duration);
            }
        }
    }
    GreatJobPlugin.info = info;
  
    return GreatJobPlugin;
  
  })(jsPsychModule);
  