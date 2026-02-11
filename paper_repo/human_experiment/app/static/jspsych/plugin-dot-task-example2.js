var jsPsychDotTaskExample2 = (function (jspsych) {
    'use strict';
  
      const info = {
          name: "dot-task-example2",
          parameters: {
              /** dot positions */
              dot_positions: {
                  type: jspsych.ParameterType.Int,
                  pretty_name: "Dot positions",
                  default: null,
              },
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
       * dot-task-example2
       * jsPsych plugin for displaying a stimulus and getting a button response
       * @author Josh de Leeuw
       * @see {@link https://www.jspsych.org/plugins/jspsych-dot-task-example2/ dot-task-example2 plugin documentation on jspsych.org}
       */
      class DotTaskExample2Plugin {
          constructor(jsPsych) {
              this.jsPsych = jsPsych;
          }
          trial(display_element, trial) {
              //success_audio.src = 'static/sounds/frog_new_sound.mp3'
              var success_audio = new Audio()
              success_audio.src = 'static/sounds/test_sound.mp3'
              var happy_audio = new Audio()
              happy_audio.src = 'static/sounds/happy_sound.mp3'
              var fail_audio = new Audio()
              fail_audio.src = 'static/sounds/splash_new_sound.mp3'
              var guess_audio = new Audio()
              guess_audio.src = 'static/sounds/guess.mp3'
              var bg_image = new Image();
              var frog_image = new Image();
              var splash_image = new Image();
              var pad_image = new Image();
              bg_image.src = 'static/imgs/pond.png'
              pad_image.src = 'static/imgs/pad.png'
              frog_image.src = 'static/imgs/frog.png'
              splash_image.src = 'static/imgs/ripple.png'
              var n_to_guess = 3
              var n_to_animate = get_display_dot_positions()[0].length - n_to_guess
              var screen_fill = 0.95
              var time_bt_jumps = 3000
              var dot_idx=0
              var default_feedback_dot_rad = 80//75
              var default_poss_region_rad = 324 
              var default_poss_region_inner_rad = 30
              var before_jump_time = 1000
              var before_allow_next_time = 1400
              var default_dot_rad = 8
              var id;
              var ignore_click = true
              var can_end = false
              function get_max_canvas_dims() {
                  return([window.innerWidth * screen_fill, window.innerHeight * screen_fill])
              }
  
              //scale all default values by this number
              //calculated based on current screen w/h
              function get_scale_from_default() {
                  var [max_canvas_w, max_canvas_h] = get_max_canvas_dims()
                  return(Math.min(max_canvas_w/trial.default_width, max_canvas_h/trial.default_height))
              }
              function touch_func(e) {
                prevent(e)
                on_click(canvas, e)
              }
              function prevent(e) {
                e.preventDefault();
              }
              //get dot positions according to true positions, default scale, and scale from default
              function get_display_dot_positions() {
                  var xs = []
                  var ys = []
                  var shift_x = trial.default_shift[0]
                  var shift_y = trial.default_shift[1]
                  var scale = trial.default_scale * get_scale_from_default()
                  for (var i = 0; i < trial.dot_positions[0].length; i++) {
                      xs.push((trial.dot_positions[0][i] + shift_x) * scale)
                      ys.push((trial.dot_positions[1][i] + shift_y) * scale)
                  }
                  var start_x = 561.6875
                  var start_y = 269.61
                  var xs = [start_x, start_x - 100, start_x - 200, start_x - 300, start_x - 400, start_x - 300, start_x - 200, start_x - 100, start_x]
                  var ys = [start_y, start_y, start_y, start_y, start_y, start_y, start_y, start_y, start_y]
                  return [xs, ys]
              }
  
              //dimensions of current screen, based on default dimensions and scale given this persons screen size
              function get_canvas_dims() {
                  var sfd = get_scale_from_default()
                  return([sfd * trial.default_width, sfd * trial.default_height])
              }
              
              function init_html() {
                  update_html()
                  animate()
              }
  
              function add_listeners(canvas) {
                  display_element
                  .querySelector("#jspsych-canvas-game-exit")
                  .addEventListener("click", () => {
                    if (can_end) {
                        end_trial()
                    }
                  });
                  var btn = document.querySelectorAll("#jspsych-canvas-game-exit");
                  btn.disabled = true
                  //maybe put these in update html and update next?
                  window.addEventListener("resize", update_html);
                  window.addEventListener("orientationchange", update_html);
                  window.addEventListener('touchmove', function(e) {
                      touch_func(e)
                  }, {passive:false}); 
                  canvas.addEventListener('mousedown', function(e) {
                    touch_func(e)
                }) 
              }
  
              function update_html() {
                  var [curr_w, curr_h] = get_canvas_dims()
                  var border_w = 1
                  var html = '<canvas id="canvas" width="' + curr_w + '" height="' + curr_h + '" style="border:' + border_w + 'px solid black;"></canvas>'
                  html +=
                  '<br><button id="jspsych-canvas-game-exit" class="jspsych-btn"' +
                  ">" +
                  "end example" +
                  "</button>";
                  display_element.innerHTML = html
                  const canvas = document.querySelector('canvas')
                  const ctx = canvas.getContext("2d");
  
                  draw_bg(ctx, curr_w, curr_h)
                  
                  //get dot positions according to true positions, default scale, and scale from default
                  var dot_positions = get_display_dot_positions()
                  var sfd = get_scale_from_default()
                  //draw dots
                  for(var i=0;i<=dot_idx;i++) {
                      //now make color relative to idx
                      var o = (i+3)/(dot_idx+3)
                      if (i==dot_idx) {
                          draw_frog(ctx, dot_positions[0][i], dot_positions[1][i], default_dot_rad * sfd, o)
                      } else {
                          draw_splash(ctx, dot_positions[0][i], dot_positions[1][i], default_dot_rad * sfd,o)
                      }
                  }
                  add_listeners(canvas)
              }   
    
              function update_html_animate() {
                  const canvas = document.querySelector('canvas')
                  const ctx = canvas.getContext("2d");
                  ctx.clearRect(0, 0, canvas.width, canvas.height);
                  draw_bg(ctx, canvas.width, canvas.height)
                  //get dot positions according to true positions, default scale, and scale from default
                  var dot_positions = get_display_dot_positions()
                  var sfd = get_scale_from_default()
                  //draw dots
                  for(var i=0;i<=dot_idx;i++) {
                      var o = (i+3)/(dot_idx+3)
                      draw_splash(ctx, dot_positions[0][i], dot_positions[1][i], default_dot_rad * sfd, o)
                  }
                  draw_splash(ctx, dot_positions[0][dot_idx+1], dot_positions[1][dot_idx+1]+5,  default_dot_rad * sfd*2,  1)
                  draw_frog(ctx, dot_positions[0][dot_idx+1], dot_positions[1][dot_idx+1],  default_dot_rad * sfd, 1)
              }  
  
              function draw_bg(ctx, w, h)
              {
                  //ctx.fillStyle = "lightskyblue";
                  //ctx.fillRect(0, 0, w, h);
                  ctx.drawImage(bg_image, 0, 0, w, h);
              }
              
              function draw_frog(ctx, x, y, rad, o)
              {
                  rad = rad*10
                  ctx.drawImage(frog_image,  x-(rad/2), y-(rad/2), rad, rad);
              }
              function draw_pad(ctx, x, y, rad, o)
              {
                  rad = rad*10
                  ctx.drawImage(pad_image,  x-(rad/2), y-(rad/2), rad, rad);
              }
              function draw_splash(ctx, x, y, rad, o)
              {
                  rad = rad*10
                  ctx.globalAlpha = o;
                  ctx.drawImage(splash_image,  x-(rad/2), y-(rad/2.2), rad, rad);
                  ctx.globalAlpha = 1;
              }

              
              setTimeout(() => {
                init_html()
              }, 200);
              

              function animate() {
                  var n_animated = 1
                  id = setInterval(animate_next, time_bt_jumps);
                  function animate_next() {
                    var dot_positions = get_display_dot_positions()
                    var x = dot_positions[0][n_animated]
                    var y = dot_positions[1][n_animated]
                    if (n_animated==n_to_animate) {
                      guess_audio.play()
                      clearInterval(id);
                      ignore_click=false;
                    } else {
                      animate_func(x, y)
                      n_animated = n_animated + 1
                    }
                  }
              }
  
              function animate_func(x,y) {
                  //current scale from default sizes
                  var sfd = get_scale_from_default()
                  //record click, scaled down in terms of true x/y coords
                  var scale = trial.default_scale * sfd
                  //check success
                  setTimeout(() => {
                      fail_audio.play();
                      setTimeout(() => {
                          update_html_animate()
                          dot_idx = dot_idx + 1
                          setTimeout(() => {
                              update_html()
                          }, 1000);
                      }, 400);
                  }, 100);
              }
              

             //draw pad at click pos
            function update_html_with_guess(x,y) {
                var canvas = document.querySelector('canvas')
                var ctx = canvas.getContext("2d");
                var sfd = get_scale_from_default()
                var dot_rad = sfd * default_dot_rad
                draw_pad(ctx, x, y, dot_rad*1.5, 1)
            }   
            function update_html_with_feedback(x,y, success) {
                //resize canvas
                const canvas = document.querySelector('canvas')
                const ctx = canvas.getContext("2d");
                ctx.clearRect(0, 0, canvas.width, canvas.height);
                draw_bg(ctx, canvas.width, canvas.height)
                //get dot positions according to true positions, default scale, and scale from default
                var dot_positions = get_display_dot_positions()
                var sfd = get_scale_from_default()
                //draw prev splashes
                for(var i=0;i<=dot_idx;i++) {
                    //now make color relative to idx
                    var o = (i+3)/(dot_idx+3)
                    draw_splash(ctx, dot_positions[0][i], dot_positions[1][i], default_dot_rad * sfd, o)
                }
                //keep lily pad
                draw_pad(ctx, x, y,  default_dot_rad * sfd*1.5, 1)
                if (!success) {
                    draw_splash(ctx, dot_positions[0][dot_idx+1], dot_positions[1][dot_idx+1], default_dot_rad * sfd*2)
                }
                draw_frog(ctx, dot_positions[0][dot_idx+1], dot_positions[1][dot_idx+1],  default_dot_rad * sfd, 1)
            } 
            function get_click_pos(canvas, click_event) {
                const rect = canvas.getBoundingClientRect()
                const x = click_event.clientX - rect.left - 1
                const y = click_event.clientY - rect.top - 1
                return [x,y]
            }
            //deal w user input
            function on_click(canvas, e) {
                var [x,y] = get_click_pos(canvas, e)
                click_func(x,y)
            }
            function click_func(x,y) {
                if(ignore_click) {
                    return;
                }
                //current dot positions
                var dot_positions = get_display_dot_positions()
                //current scale from default sizes
                var sfd = get_scale_from_default()
                if (check_valid(x, y, dot_positions, sfd)) {
                    //record rt

                    //record click, scaled down in terms of true x/y coords
                    var scale = trial.default_scale * sfd
                    var shift_x = trial.default_shift[0]
                    var shift_y = trial.default_shift[1]
                    
                    //check success
                    var success = check_success(x, y, dot_positions, sfd)

                    //update html with feedback / next dot
                    display_feedback(success, x, y)
                }
            }

            //check if valid or successful click, computations done in terms of display positions
            //could also do in terms of true positions but this is easier
            function check_success(x,y, dot_positions, sfd) {
                var feedback_dot_rad = default_feedback_dot_rad * sfd
                var true_x = dot_positions[0][dot_idx+1]
                var true_y = dot_positions[1][dot_idx+1]
                return (Math.hypot(x - true_x, y - true_y) < feedback_dot_rad)
            }
            function check_valid(x, y, dot_positions, sfd) {
                var poss_region_rad = sfd * default_poss_region_rad
                var poss_region_inner_rad = sfd * default_poss_region_inner_rad

                var prev_x = dot_positions[0][dot_idx]
                var prev_y = dot_positions[1][dot_idx]
                var d = Math.hypot(x - prev_x, y - prev_y)
                return (d > poss_region_inner_rad)
                return ((d < poss_region_rad) && (d > poss_region_inner_rad))
            }

            function display_feedback(success, x, y) {
                //don't let user give another response until html has updated
                ignore_click=true;
                //show pad at click pos
                update_html_with_guess(x,y)
                //wait 500 ms before showing red or green
                setTimeout(() => {
                    if (success) {
                        success_audio.play();
                    } else {
                        fail_audio.play();
                    }
                }, 100);
                setTimeout(() => {
                    //draw frog and next pos
                    update_html_with_feedback(x,y, success)
                    dot_idx = dot_idx + 1
                    //after 500 ms, (1000 in total) remove everything, start timer, and allow clicks again
                    //and if its time to move on, update the html with the new dot and new poss region
                    setTimeout(() => {
                        if (dot_idx >= get_display_dot_positions()[0].length-1) {//trial.dot_positions[0].length-1) {
                            ignore_click=true
                            can_end = true;
                            update_html()
                            var btn = document.querySelectorAll("#jspsych-canvas-game-exit");
                            btn.disabled = false
                        } else {
                            //do this no matter what to clear feedback, show next dot if dot_idx increase
                            update_html()
                            ignore_click=false;
                            //start clock once they can click agaun, after feedback has been displayed
                        };
                    }, before_allow_next_time);
                }, before_jump_time);
            };

              // function to end trial when it is time
              const end_trial = () => {
                  // kill any remaining setTimeout handlers
                  this.jsPsych.pluginAPI.clearAllTimeouts();
                  // gather the data to store for the trial
                  var trial_data = {
                      rt: 100,
                  };
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
                  window.removeEventListener("resize",update_html);
                  window.removeEventListener("orientationchange",update_html);
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
      DotTaskExample2Plugin.info = info;
  
      return DotTaskExample2Plugin;
  
  })(jsPsychModule);
  