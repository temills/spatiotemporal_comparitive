var jsPsychDotTaskExample1 = (function (jspsych) {
    'use strict';
  
      const info = {
          name: "dot-task-example1",
          parameters: {
              /** default values, dear god kill me */
              default_scale: {
                  type: jspsych.ParameterType.Int,
                  pretty_name: "default scale for dot positions",
                  default: null,
              },
              default_shift: {
                  type: jspsych.ParameterType.Int,
                  pretty_name: "shift x/y",
                  default: null,
              },
              default_width: {
                  type: jspsych.ParameterType.Int,
                  pretty_name: "default width of rect",
                  default: null,
              },
              default_height: {
                  type: jspsych.ParameterType.Int,
                  pretty_name: "defualt height of rect",
                  default: null,
              },
          },
      };
      /**
       * dot-task-example1
       * jsPsych plugin for displaying a stimulus and getting a button response
       * @author Josh de Leeuw
       * @see {@link https://www.jspsych.org/plugins/jspsych-dot-task-example1/ dot-task-example1 plugin documentation on jspsych.org}
       */
      class DotTaskExample1Plugin {
            constructor(jsPsych) {
                this.jsPsych = jsPsych;
            }
            trial(display_element, trial) {
                
                var success_audio = new Audio()
                success_audio.src = 'static/sounds/frog_sound.mp3'
                var sad_audio = new Audio()
                sad_audio.src = 'static/sounds/disappear_sound.mp3'
                var sad_audio1 = new Audio()
                sad_audio1.src = 'static/sounds/thunder_sound.mp3'
                
                var ready_to_end = false
                var start_animate = true
                var screen_fill = 0.95
                var time_bt_jumps = 2000
                var default_dot_rad = 8
                var pad_idxs = [1,9,16,21]
                var id1;
                var id2;
   
                var images = [];
                // Array to hold the image URLs

                // Counter to keep track of the number of images loaded
                var imagesLoaded = 0;
                // Array to hold the image URLs
                var imageUrls = [
                    'static/imgs/pond.png',
                    'static/imgs/pad.png',
                    'static/imgs/frog.png',
                    'static/imgs/ripple.png'
                ];

                function handleImageLoad() {
                    imagesLoaded++;
                    // Check if all images have finished loading
                    if (imagesLoaded === imageUrls.length) {
                        init_html()
                    }
                }
                function LoadImages() {
                    for (var i = 0; i < imageUrls.length; i++) {
                        var image = new Image();
                        image.src = imageUrls[i];
                        image.onload = handleImageLoad;
                        images.push(image);
                    }
                }
                LoadImages()
            

                function get_pad_positions() {
                    var pad_positions = []
                    var [w, h] = get_canvas_dims()
                    //6 cols, alternating 4 and 3 pads
                    for(var i=0;i<7;i++) {
                        var x = (((w)/7) * (i))
                        if (i%2==0) {
                            for(var j=0;j<4;j++) {
                            var y = (((h)/4) * (j))
                            pad_positions.push([x+(w/(7*2)),y+(h/(4*2))])
                            }
                        } else {
                            for(var j=0;j<3;j++) {
                                var y = (((h)/3) * (j)) 
                                pad_positions.push([x+(w/(7*2)),y+(h/(3*2))])
                            }
                        }
                    }
                    return pad_positions
                }


                function get_max_canvas_dims() {
                    return([window.innerWidth * screen_fill, window.innerHeight * screen_fill])
                }
  
                //scale all default values by this number
                //calculated based on current screen w/h
                function get_scale_from_default() {
                    var [max_canvas_w, max_canvas_h] = get_max_canvas_dims()
                    return(Math.min(max_canvas_w/trial.default_width, max_canvas_h/trial.default_height))
                }
                //dimensions of current screen, based on default dimensions and scale given this persons screen size
                function get_canvas_dims() {
                    var sfd = get_scale_from_default()
                    return([sfd * trial.default_width, sfd * trial.default_height])
                }
              

                function prevent(e) {
                    e.preventDefault();
                }
                function touch_func(e) {
                    prevent(e)
                }

                function disable_next() {
                    display_element.querySelector("#jspsych-canvas-game-ok").disabled = true;
                }
                function enable_next() {
                    display_element.querySelector("#jspsych-canvas-game-ok").disabled = false;
                }

                function add_listeners(canvas) {
                    //add click listener
                    display_element
                    .querySelector("#jspsych-canvas-game-ok")
                    .addEventListener("click", () => {
                        if (start_animate) {
                            animate()  
                            disable_next()
                            start_animate = false
                        } else {
                            if (ready_to_end) {
                                end_trial()
                            } else {
                            animate2()
                            disable_next()
                            }
                        }
                    });
  
                    window.addEventListener('touchmove', function(e) {
                        touch_func(e)
                    }, {passive:false});  
                }
  
                function init_html() {
                    var [curr_w, curr_h] = get_canvas_dims()
                    var border_w = 1
                    var html =
                    '<div style="position:absolute; left:10px;"><button id="jspsych-canvas-game-ok" class="jspsych-btn"' +
                    ">" +
                    ">>" +
                    "</button></div>";
                    html += '<canvas id="canvas" width="' + curr_w + '" height="' + curr_h + '" style="border:' + border_w + 'px solid black;"></canvas>'
                    display_element.innerHTML = html
                    const canvas = document.querySelector('canvas')
                    canvas.style.userSelect = 'none';
                    canvas.style.webkitTouchCallout = 'none';
                    canvas.style.webkitUserSelect = 'none';
                    canvas.style.khtmlUserSelect = 'none';
                    canvas.style.mozUserSelect = 'none';
                    canvas.style.msUserSelect = 'none';
                    canvas.style.webkitTapHighlightColor = 'transparent';
                    canvas.style.webkitTapHighlightColor = 'rgba(0,0,0,0)';
                    const ctx = canvas.getContext("2d");
                    var sfd = get_scale_from_default()

                    draw_bg(ctx, curr_w, curr_h)
                    var pad_positions = get_pad_positions()
                    for (var i=0; i<pad_positions.length; i++) {
                        draw_pad(ctx, pad_positions[i][0], pad_positions[i][1], default_dot_rad * sfd*1.5, 1)
                    }
                    draw_frog(ctx, pad_positions[pad_idxs[0]][0], pad_positions[pad_idxs[0]][1], default_dot_rad * sfd, 1)
                    add_listeners(canvas)
                }   
    
                function update_frog_pos(x,y) {
                    var [curr_w, curr_h] = get_canvas_dims()
                    const canvas = document.querySelector('canvas')
                    const ctx = canvas.getContext("2d");
                    ctx.clearRect(0, 0, canvas.width, canvas.height);
                    draw_bg(ctx, curr_w, curr_h)
                    var pad_positions = get_pad_positions()
                    var sfd = get_scale_from_default()
                    for (var i=0; i<pad_positions.length; i++) {
                        draw_pad(ctx, pad_positions[i][0], pad_positions[i][1], default_dot_rad * sfd*1.5, 1)
                    }
                    draw_frog(ctx, x, y, default_dot_rad * sfd, 1)
                }  

                function fade_out(o) {
                    const canvas = document.querySelector('canvas')
                    const ctx = canvas.getContext("2d");
                    ctx.clearRect(0,0,canvas.width,canvas.height);
                    draw_bg(ctx, canvas.width,canvas.height)
                    var pad_positions = get_pad_positions()
                    var sfd = get_scale_from_default()
                    for (var i=0; i<pad_positions.length; i++) {
                        draw_pad(ctx, pad_positions[i][0], pad_positions[i][1], default_dot_rad * sfd*1.5, o)
                    }
                    draw_frog(ctx, pad_positions[pad_idxs[pad_idxs.length-1]][0], pad_positions[pad_idxs[pad_idxs.length-1]][1], default_dot_rad * sfd, 1)
                }  
  
                function draw_bg(ctx, w, h)
                {
                    ctx.drawImage(images[0], 0, 0, w, h);
                }
              
                function draw_frog(ctx, x, y, rad, o)
                {
                    rad = rad*10
                    ctx.drawImage(images[2],  x-(rad/2), y-(rad/2), rad, rad);
                }
                function draw_pad(ctx, x, y, rad, o)
                {
                    rad = rad*10
                    ctx.globalAlpha = o;
                    ctx.drawImage(images[1],  x-(rad/2), y-(rad/2), rad, rad);
                    ctx.globalAlpha = 1;
                }
          
                function animate() {
                    var n_animated = 1
                    id1 = setInterval(animate_next, time_bt_jumps);
                    function animate_next() {
                        if (n_animated>=pad_idxs.length) {
                            clearInterval(id1);
                            enable_next()
                        } else {
                            var pad_positions = get_pad_positions()
                            var x = pad_positions[pad_idxs[n_animated]][0]
                            var y = pad_positions[pad_idxs[n_animated]][1]
                            animate_func(x, y)
                            n_animated = n_animated + 1
                        }
                    }
                }
                var temp_idx = 0
                function animate_func(x,y) {
                    if (temp_idx == 0) {
                        success_audio.play();
                    } else if (temp_idx ==1) {
                        success_audio.play();
                    } else {
                        success_audio.play();
                    }
                    temp_idx = temp_idx + 1
                    //setTimeout(() => {
                    update_frog_pos(x,y)
                    //}, 300);
                }

                function animate2() {
                    clearInterval(id1);
                    sad_audio1.play();
                    setTimeout(() => {
                        sad_audio.play();
                        var o = 1
                        id2 = setInterval(animate2_next, 50);
                        function animate2_next() {
                            if (o<0.05) {
                                clearInterval(id2);
                                ready_to_end = true
                                enable_next()
                            } else {
                                fade_out(o)
                                o = o * 0.95
                            }
                        }
                    }, 2000);
                }
              
                // function to end trial when it is time
                const end_trial = () => {
                    // kill any remaining setTimeout handlers
                    this.jsPsych.pluginAPI.clearAllTimeouts();
                    clearInterval(id1)
                    clearInterval(id2)
                    // gather the data to store for the trial
                    var trial_data = {
                        rt: 100,
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
                    var wheelEvent = 'onwheel' in document.createElement('div') ? 'wheel' : 'mousewheel';                
                    window.removeEventListener(wheelEvent, function(e) {
                        prevent(e)
                    }, {passive:false}); 
                    */
                    // clear the display
                    display_element.innerHTML = "";
                    // move on to the next trial
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
                  stimulus: trial.stimulus,
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
      DotTaskExample1Plugin.info = info;
  
      return DotTaskExample1Plugin;
  
  })(jsPsychModule);
  