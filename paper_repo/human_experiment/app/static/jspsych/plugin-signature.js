var jsPsychSignature = (function (jspsych) {
    'use strict';
  
    const info = {
        name: "signature",
        parameters: {
            /** The drawing function to apply to the canvas. Should take the canvas object as argument. */
            stimulus: {
                type: jspsych.ParameterType.FUNCTION,
                pretty_name: "Stimulus",
                default: undefined,
            },
            /** How long to hide the stimulus. */
            stimulus_duration: {
                type: jspsych.ParameterType.INT,
                pretty_name: "Stimulus duration",
                default: null,
            },
            /** How long to show the trial. */
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
            /** If true, then trial will end when user responds. */
            response_ends_trial: {
                type: jspsych.ParameterType.BOOL,
                pretty_name: "Response ends trial",
                default: true,
            },
            /** Array containing the height (first value) and width (second value) of the canvas element. */
            canvas_size: {
                type: jspsych.ParameterType.INT,
                array: true,
                pretty_name: "Canvas size",
                default: [500, 500],
            },
        },
    };
    /**
     * **signature**
     *
     * jsPsych plugin for displaying a canvas stimulus and getting a button response
     *
     * @author Chris Jungerius (modified from Josh de Leeuw)
     * @see {@link https://www.jspsych.org/plugins/jspsych-signature/ signature plugin documentation on jspsych.org}
     */
    class SignaturePlugin {
        constructor(jsPsych) {
            this.jsPsych = jsPsych;
        }
        trial(display_element, trial) {
            function prevent(e) {
                e.preventDefault();
            }
            function touch_func(e) {
               prevent(e)
            }
            // create canvas
            var img_url = ""
            var can_submit = false
            var html = ''
            html += '<div><img src="static/imgs/consent.png" style="width:900px;"></div>',
            
            html += '<br><br><div><b>Signature:</b></div>'
            html += '<div id="jspsych-signature-stimulus">' +
                '<canvas id="jspsych-canvas-stimulus" height="' +
                100 +
                '" width="' +
                400 +
                '" style="border:' + 1 + 'px solid black;"' +
                '"></canvas>' +
                "</div>";
            //display buttons
            html +=
            '<br><button id="jspsych-signature-submit" class="jspsych-btn"' +
            ">" +
            "submit" +
            "</button>";
            /*
            html +=
            '<button id="jspsych-signature-clear" class="jspsych-btn"' +
            ">" +
            "clear" +
            "</button>";
            */

            display_element.innerHTML = html;
            let writingMode = false;
            let canvas = document.getElementById("jspsych-canvas-stimulus");
            const ctx = canvas.getContext("2d");
            const handlePointerDown = (event) => {
                can_submit = true
                writingMode = true;
                ctx.beginPath();
                const [positionX, positionY] = getCursorPosition(event);
                ctx.moveTo(positionX, positionY);
            }
            const handlePointerUp = () => {
                writingMode = false;
            }
            
            const handlePointerMove = (event) => {
                if (!writingMode) return
                const [positionX, positionY] = getCursorPosition(event);
                ctx.lineTo(positionX, positionY);
                ctx.stroke();
            }
            const getCursorPosition = (event) => {
                const positionX = event.clientX - event.target.getBoundingClientRect().x;
                const positionY = event.clientY - event.target.getBoundingClientRect().y;
                return [positionX, positionY];
            }
            canvas.addEventListener('pointerdown', handlePointerDown, {passive: true});
            canvas.addEventListener('pointerup', handlePointerUp, {passive: true});
            canvas.addEventListener('pointermove', handlePointerMove, {passive: true});
            ctx.lineWidth = 3;
            ctx.lineJoin = ctx.lineCap = 'round';
            
            const clearPad = () => {
                ctx.clearRect(0, 0, canvas.width, canvas.height);
            }

            // add event listeners to buttons
            display_element
                .querySelector("#jspsych-signature-submit")
                .addEventListener("click", (e) => {
                    if (can_submit) {
                        img_url = canvas.toDataURL();
                        clearPad();
                        end_trial()
                    }
            });
            /*
            display_element
              .querySelector("#jspsych-signature-clear")
              .addEventListener("click", (e) => {
                e.preventDefault();
                clearPad();
              })
            */
            // store response
            var response = {
                rt: null,
                button: null,
            };

            window.addEventListener('touchmove', function(e) {
                touch_func(e)
            }, {passive:false});  
            /*
            window.addEventListener(wheelEvent, function(e) {
                prevent(e)
            }, {passive:false}); 
            */ 
            //$('body').bind('touchmove', function(e){e.preventDefault()})
            // function to end trial when it is time
            const end_trial = () => {
                // kill any remaining setTimeout handlers
                this.jsPsych.pluginAPI.clearAllTimeouts();
                // gather the data to store for the trial
                var trial_data = {
                    img_url: img_url,
                };
                /*
                window.removeEventListener('touchstart', function(e) {
                    prevent(e)
                }, {passive:false});  
                */
                window.removeEventListener('touchmove', function(e) {
                    touch_func(e)
                }, {passive:false});  
                /*
                window.removeEventListener(wheelEvent, function(e) {
                    prevent(e)
                }, {passive:false}); 
                */
                // clear the display
                display_element.innerHTML = "";
                // move on to the next trial
                var img_url = canvas.toDataUrl()
                trial_data = {"img": img_url}
                this.jsPsych.finishTrial(trial_data);
            };
            
        }

        simulate(trial, simulation_mode, simulation_options, load_callback) {
            if (simulation_mode == "data-only") {
                load_callback();
                this.simulate_data_only(trial, simulation_options);
            }
            if (simulation_mode == "visual") {
                this.simulate_visual(trial, simulation_options, load_callback);
            }
        }
        create_simulation_data(trial, simulation_options) {
            const default_data = {
                rt: this.jsPsych.randomization.sampleExGaussian(500, 50, 1 / 150, true),
                response: this.jsPsych.randomization.randomInt(0, trial.choices.length - 1),
            };
            const data = this.jsPsych.pluginAPI.mergeSimulationData(default_data, simulation_options);
            this.jsPsych.pluginAPI.ensureSimulationDataConsistency(trial, data);
            return data;
        }
        simulate_data_only(trial, simulation_options) {
            const data = this.create_simulation_data(trial, simulation_options);
            this.jsPsych.finishTrial(data);
        }
        simulate_visual(trial, simulation_options, load_callback) {
            const data = this.create_simulation_data(trial, simulation_options);
            const display_element = this.jsPsych.getDisplayElement();
            this.trial(display_element, trial);
            load_callback();
            if (data.rt !== null) {
                this.jsPsych.pluginAPI.clickTarget(display_element.querySelector(`div[data-choice="${data.response}"] button`), data.rt);
            }
        }
    }
    SignaturePlugin.info = info;
  
    return SignaturePlugin;
  
  })(jsPsychModule);