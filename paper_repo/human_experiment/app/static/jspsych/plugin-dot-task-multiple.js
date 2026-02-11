var jsPsychDotTaskMultiple = (function (jspsych) {
    'use strict';
  
      const info = {
          name: "dot-task-multiple",
          parameters: {
              /** dot positions */
              dot_positions: {
                  type: jspsych.ParameterType.Int,
                  pretty_name: "Dot positions",
                  default: null,
              },
              /** dot positions */
              stimulus: {
                  type: jspsych.ParameterType.Int,
                  pretty_name: "stim",
                  default: null,
              },
              default_scale: {
                  type: jspsych.ParameterType.Int,
                  pretty_name: "default scale for dot positions",
                  default: null,
              },
              n_to_animate: {
                  type: jspsych.ParameterType.Int,
                  pretty_name: "n to animate",
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
       * dot-task-multiple
       * jsPsych plugin for displaying a stimulus and getting a button response
       * @author Josh de Leeuw
       * @see {@link https://www.jspsych.org/plugins/jspsych-dot-task-multiple/ dot-task-multiple plugin documentation on jspsych.org}
       */
      class DotTaskMultiplePlugin {
          constructor(jsPsych) {
              this.jsPsych = jsPsych;
          }
          trial(display_element, trial) {
              //success_audio.src = 'static/sounds/frog_new_sound.mp3'
              
              var success_audio = new Audio()
              success_audio.src = 'static/sounds/success_sound.mp3'
              var fail_audio = new Audio()
              var guess_audio = new Audio()
              guess_audio.src = 'static/sounds/guess_sound.mp3'
              fail_audio.src = 'static/sounds/fail_sound.mp3'
              
              var n_to_animate = trial.n_to_animate
              var do_memory_task = true
              var n_guesses_before_feedback = 3
              if (do_memory_task) {
                  var n_guesses_before_feedback = n_to_animate + n_guesses_before_feedback
              }
  
  
  
              var screen_fill = 0.95
              var before_jump_time = 600
              var before_allow_next_time = 1000
              var id;
              var default_dot_rad = 8 * 8
              var default_prev_pt_rad = 20
              var guess_rad = 50
              var default_feedback_dot_rad = 80//75
              var default_poss_region_rad = 324 
              var default_poss_region_inner_rad = 30
              var animate_interval_time = 1300
              var animate_over = false;
              var side_bar_width = 50
              const scaleSpeed = 0.04; // Rate of scale increase
              var init_scale = 0.7
              const angleSpeed = 0//2*Math.PI/(((1-init_scale)/scaleSpeed)-0.5)
              var meter_ct = 1
  
              var images = [];
              var prev_loc = []
              var rcanvas = ""
              var rctx = ""
              var canvas = ""
              var ctx = ""
  
              // Array to hold the image URLs
              var imageUrls = [
                'static/imgs/purp.png',
                'static/imgs/pnksprk.png',
                'static/imgs/bar.png',
                'static/imgs/star2.png',
                'static/imgs/star.png',
                'static/imgs/outline.png',
                'static/imgs/barfill.png'
              ];
              var imagesLoaded = 0;
              function handleImageLoad() {
                imagesLoaded++;
                // Check if all images have finished loading
                if (imagesLoaded === imageUrls.length) {
                    init_html()
                    update_html()
                    animate()
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
  
  
  
              function get_max_canvas_dims() {
                  return([window.innerWidth * screen_fill, window.innerHeight * screen_fill])
              }
  
              //scale all default values by this number
              //calculated based on current screen w/h
              function get_scale_from_default() {
                  var [max_canvas_w, max_canvas_h] = get_max_canvas_dims()
                  return(Math.min(max_canvas_w/trial.default_width, max_canvas_h/trial.default_height))
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
                  return [xs,ys]
              }
              function prevent(e) {
                  e.preventDefault();
              }
              function on_click_prevent_default(e) {
                  prevent(e)
                  on_click(canvas, e)
              }
              //dimensions of current screen, based on default dimensions and scale given this persons screen size
              function get_canvas_dims() {
                  var sfd = get_scale_from_default()
                  return([sfd * trial.default_width, sfd * trial.default_height])
              }
              
  
              function add_listeners(canvas) {
                  //add click listener
                  display_element
                  .querySelector("#jspsych-canvas-game-exit")
                  .addEventListener("click", () => {
                      if (animate_over) {
                          end_trial()
                      } else {
                          clearInterval(id);
                          setTimeout(() => {
                              end_trial()
                          }, animate_interval_time+100);
                      }
                  });
                  //maybe put these in update html and update next?
                  window.addEventListener("resize", update_html);
                  window.addEventListener("orientationchange", update_html);
                  canvas.addEventListener('mousedown', function(e) {
                      on_click(canvas, e)
                  })
                  window.addEventListener('touchmove', function(e) {
                      e.preventDefault();
                  }, {passive:false});
                  canvas.addEventListener('touchstart', function(e) {
                      e.preventDefault();
                      on_click(canvas, e)
                  }, false)
              }
  
              function prevent_highlight(canv) {
                  canv.style.userSelect = 'none';
                  canv.style.webkitTouchCallout = 'none';
                  canv.style.webkitUserSelect = 'none';
                  canv.style.khtmlUserSelect = 'none';
                  canv.style.mozUserSelect = 'none';
                  canv.style.msUserSelect = 'none';
                  canv.style.webkitTapHighlightColor = 'transparent';
                  canv.style.webkitTapHighlightColor = 'rgba(0,0,0,0)';
              }
  
              function init_html() {
                  var [curr_w, curr_h] = get_canvas_dims()
                  var border_w = 0
                  var html =
                  '<div style="position:absolute; left:10px;"><button id="jspsych-canvas-game-exit" class="jspsych-btn"' +
                  ">" +
                  "exit" +
                  "</button></div>";
                  
                  html += '<div class="canvas-container" style="width:' + curr_w + 'px; height:' + curr_h + 'px;">' +
                          '<canvas id="rotatingCanvas" width="' + (curr_w) + '" height="' + (curr_h) + '"></canvas>' +
                          '<canvas id="staticCanvas" width="' + (curr_w) + '" height="' + curr_h + '" style="border:' + border_w + 'px solid black;"></canvas>' +
                          '</div>'
                  
                  display_element.innerHTML = html
                  //make canvas non-selectable
                  canvas = document.getElementById('staticCanvas')
                  ctx = canvas.getContext("2d");
                  draw_bg(ctx, curr_w, curr_h)
                  rcanvas = document.getElementById('rotatingCanvas');
                  rctx = rcanvas.getContext('2d');
                  //rctx.fillStyle = "green";
                  //rctx.fillRect(0, 0, rcanvas.width, rcanvas.height);
                  add_listeners(rcanvas)
                  prevent_highlight(rcanvas)
                  prevent_highlight(canvas)
                  prev_loc = []
              }


            function animate_fade() {
                var o = 0.05
                var id2 = setInterval(animate_next, 50);
                var [curr_w, curr_h] = get_canvas_dims()
                function animate_next() {
                    if (o>0.9) {
                        rctx.globalAlpha = 1
                        clearInterval(id2);
                    } else {
                        rctx.globalAlpha = o
                        console.log("drawing bg")
                        draw_bg(rctx, curr_w, curr_h)
                        var dot_positions = get_display_dot_positions()
                        var sfd= get_scale_from_default()
                        //draw_star([dot_positions[0][0], dot_positions[1][0]], default_dot_rad * sfd, rctx)
                        o = o * 1.1
                    }
                }
            }


            function animate_end() {
                var o = 0.05
                var id2 = setInterval(animate_next, 50);
                var [curr_w, curr_h] = get_canvas_dims()
                function animate_next() {
                    if (o>0.9) {
                        rctx.globalAlpha = 1
                        clearInterval(id2);
                    } else {
                        rctx.globalAlpha = o
                        draw_bg(rctx, curr_w, curr_h)
                        draw_star([curr_w/2, curr_h/2], curr_w/2, rctx)
                        o = o * 1.1
                    }
                }
            }
              
              var arrow_speed = 0.06
              //given progress from pt1 to pt2, get current loc
              function get_curr_loc(prev_loc, loc, progress) {
                  progress = Math.min(progress,1)
                  var curr_w = get_canvas_dims()[0]
                  var curr_x = prev_loc[0] + (loc[0] - prev_loc[0]) * progress;
                  var curr_y = prev_loc[1] + (loc[1] - prev_loc[1]) * progress;
                  var vec = [curr_x-prev_loc[0], curr_y-prev_loc[1]]
                  var mag = Math.sqrt((vec[0]*vec[0]) + (vec[1]*vec[1]))
                  if (mag>0) {
                      var norm_vec = [vec[0]/mag, vec[1]/mag]
                      var [curr_x, curr_y] = [curr_x - (norm_vec[0]), curr_y - (norm_vec[1])]
                  }
                  return([curr_x, curr_y])
              }
  
              //static html at curr point
              //simply clear animation screen and draw star on it
              function update_html() {
                  //remove last spinny star
                  //ctx.clearRect(0, 0, rcanvas.width, rcanvas.height);
                  //get dot positions according to true positions, default scale, and scale from default
                  var dot_positions = get_display_dot_positions()
                  var sfd = get_scale_from_default()
                  //draw latest dot
                  draw_prev_pt([dot_positions[0][dot_idx], dot_positions[1][dot_idx]], default_prev_pt_rad * sfd, ctx)
                  //draw star over dot on rctx
                  rctx.clearRect(0, 0, rcanvas.width, rcanvas.height);
                  draw_star([dot_positions[0][dot_idx], dot_positions[1][dot_idx]], default_dot_rad * sfd, rctx)
                  prev_loc = [dot_positions[0][dot_idx], dot_positions[1][dot_idx]]
                  console.log("here")
              } 


              function reset_html() {
                ctx.clearRect(0, 0, rcanvas.width, rcanvas.height);
                var [curr_w, curr_h] = get_canvas_dims()
                draw_bg(ctx, curr_w, curr_h)
                update_html()
              }
                      
              function animate() {
                  var n_animated = 0
                  id = setInterval(animate_next, animate_interval_time);
                  function animate_next() {
                    if (n_animated==n_to_animate) {
                      console.log("last one")
                      clearInterval(id);
                      animate_over = true;
                      //guess_audio.play();
                      if (do_memory_task) {
                          dot_idx=0
                          animate_fade()
                          setTimeout(() => {
                            guess_audio.play()
                            reset_html()
                          }, 1600)
                          setTimeout(() => {
                            ignore_click=false;
                            start_time = performance.now();
                          }, 2000)
                      } else {
                        update_html()
                        ignore_click=false;
                        start_time = performance.now();
                      }
                    } else {
                        scale_at_click[dot_idx] = trial.default_scale * get_scale_from_default()
                        //check success
                        setTimeout(() => {
                            //fail_audio.play();
                            setTimeout(() => {
                                var dot_positions = get_display_dot_positions()
                                animate_one(0, [dot_positions[0][dot_idx], dot_positions[1][dot_idx]], [dot_positions[0][dot_idx+1], dot_positions[1][dot_idx+1]], null, 0)
                                update_html()
                                prev_loc = [dot_positions[0][dot_idx+1], dot_positions[1][dot_idx+1]]
                                dot_idx = dot_idx + 1
                            }, 200);
                        }, 100);
                      n_animated = n_animated + 1
                    }
                  }
              }
  
  
              //animate star shooting to next point
              //add dots and prev pt to ctx
              //and move star on rctx
              //also draw guesses on rctx
              function animate_one(progress, prev_loc, loc, guesses, n_calls) {
                  //var sfd = get_scale_from_default()
                  var [curr_w, curr_h] = get_canvas_dims()
                  rctx.clearRect(0, 0, rcanvas.width, rcanvas.height);
                  //draw guess
                  var sfd = get_scale_from_default()
                  if (!(guesses==null)) {
                      for (var i=0; i<guesses.length; i++) {
                          draw_guess(guesses[i], guess_rad*sfd, rctx)
                      }
                  }
                  //draw arrow
                  var curr_loc = get_curr_loc(prev_loc, loc, progress)
                  if (n_calls%2==0) {
                      draw_dot(curr_loc, 2*sfd, ctx)
                  }
                  //draw_arrow(prev_loc, curr_loc, rctx) 
                  if (progress>=1) {
                    draw_star(loc,  sfd * default_dot_rad, rctx)
                  } else {
                    draw_star(curr_loc,  sfd * default_dot_rad, rctx)
                  }
                  if (progress < 1) {
                      //request the next animation frame
                      requestAnimationFrame(animate_one.bind(null, progress + arrow_speed, prev_loc, loc, guesses, n_calls+1));
                  }
              }

              function animate_guess(progress, prev_loc, loc, guesses, n_calls) {
                //var sfd = get_scale_from_default()
                var [curr_w, curr_h] = get_canvas_dims()
                rctx.clearRect(0, 0, rcanvas.width, rcanvas.height);
                //draw guess
                var sfd = get_scale_from_default()
                if (!(guesses==null)) {
                    for (var i=0; i<guesses.length; i++) {
                        draw_guess(guesses[i], guess_rad*sfd, rctx)
                    }
                }
                //draw arrow
                var curr_loc = get_curr_loc(prev_loc, loc, progress)
                if (n_calls%2==0) {
                    draw_dot(curr_loc, 2*sfd, ctx)
                }
                //draw_arrow(prev_loc, curr_loc, rctx) 
                draw_guess(curr_loc,  sfd * default_dot_rad, rctx)
                if (progress < 1) {
                    //request the next animation frame
                    requestAnimationFrame(animate_guess.bind(null, progress + arrow_speed, prev_loc, loc, guesses, n_calls+1));
                } else {
                    draw_prev_pt(loc, default_prev_pt_rad*sfd, ctx)
                }
            }
  
              function draw_bg(curr_ctx, w, h)
              {
                  
                  curr_ctx.drawImage(images[0], 0, 0, w, h);
              }
              
              function draw_guess(loc, rad, curr_ctx)
              {
                curr_ctx.drawImage(images[4],  loc[0]-(rad/2), loc[1]-(rad/2), rad, rad);
              }
  
              function draw_star(loc, rad, curr_ctx)
              {
                  //curr_ctx.globalAlpha = o;
                  curr_ctx.drawImage(images[4],  loc[0]-(rad/2), loc[1]-(rad/2), rad, rad);
                  //curr_ctx.globalAlpha = 1;
              }
  
              function draw_prev_pt(loc, rad, curr_ctx)
              {
                  curr_ctx.drawImage(images[3],  loc[0]-(rad/2), loc[1]-(rad/2), rad, rad);
                  /*curr_ctx.fillStyle = "yellow";
                  curr_ctx.beginPath();
                  curr_ctx.arc(loc[0], loc[1], rad, 0, 2*Math.PI);
                  curr_ctx.fill();*/
              }
              function draw_dot(loc, rad, curr_ctx)
              {
                  curr_ctx.fillStyle = "rgb(255,230,0)";
                  curr_ctx.beginPath();
                  curr_ctx.arc(loc[0], loc[1], rad, 0, 2*Math.PI);
                  curr_ctx.fill();
              }
  
  
              // initialize stuff
              var start_time = performance.now();
              var scale_at_click = []
              var click_x = [];
              var click_y = [];
              var guess_success = [];
              var dot_idx = 0;
              var rts = []
              for (var i = 0; i < trial.dot_positions[0].length; i++) {
                  click_x.push(null)
                  click_y.push(null)
                  scale_at_click.push(null)
                  guess_success.push(null)
                  rts.push(null)
              }
  
              var end_time = null;
              var ignore_click = true;
  
  
              function get_click_pos(canvas, click_event) {
                const rect = canvas.getBoundingClientRect()
                try {
                    var x = click_event.touches[0].clientX - rect.left - 1
                    var y = click_event.touches[0].clientY - rect.top - 1
                  } catch (error) {
                    var x = click_event.clientX - rect.left - 1
                    var y = click_event.clientY - rect.top - 1
                  }
                return [x,y]
            }
              
              //deal w user input
              function on_click(canvas, e) {
                console.log("click")
                  if(ignore_click) {
                      return;
                  }
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
                      ignore_click=true;
                      //record rt
                      end_time = performance.now();
                      rts[dot_idx] = end_time - start_time;
  
                      //record click, scaled down in terms of true x/y coords
                      var scale = trial.default_scale * sfd
                      var shift_x = trial.default_shift[0]
                      var shift_y = trial.default_shift[1]
                      click_x[dot_idx] = (x/scale)-shift_x
                      click_y[dot_idx] = (y/scale)-shift_y
                      scale_at_click[dot_idx] = scale
                      
                      //check success
                      var success = check_success(x, y, dot_positions, sfd)
                      guess_success[dot_idx] = success
  
                      //update html with feedback / next dot
                      display_feedback(success, x, y)
                  }
              }
  
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
              }
  
  
              function display_feedback(success, x, y) {
                  //show pad at click pos
                  var sfd = get_scale_from_default()
                  var dot_rad = sfd * default_dot_rad
                  var dot_positions = get_display_dot_positions()
                  animate_guess(0, prev_loc, [x, y], null, 0)
                  //update static

                  prev_loc = [x,y]
                  dot_idx = dot_idx + 1
                  setTimeout(() => {
                    if (dot_idx == trial.dot_positions[0].length) {
                        ignore_click=true
                        animate_end()
                        success_audio.play()
                        setTimeout(() => {
                            end_trial()
                        }, 2000);
                    } else {
                        ignore_click=false;
                        start_time = performance.now();
                    }
                    //fail_audio.play();
                  }, 500);
                /*
                  } else { //only sometimes display feedback
                      //animate
                      var i = 0
                      var id = setInterval(animate_next, before_jump_time);
                      function animate_next() {
                        if (i==n_guesses_before_feedback || (dot_idx >= trial.dot_positions[0].length-1)) {
                          clearInterval(id);
                          if (dot_idx >= trial.dot_positions[0].length-1) {
                              end_trial()
                          }
                          ignore_click=false;
                          update_html()
                          start_time = performance.now();
                          guess_num = 0
                        } else {
                          var display_idx = (dot_idx-n_guesses_before_feedback)+i
                          success = guess_success[display_idx]
                          var display_guesses = []
                          for (var j=display_idx; j<dot_idx; j++) {
                              display_guesses.push([(click_x[j]+trial.default_shift[0])*scale_at_click[j], (click_y[j]+trial.default_shift[1])*scale_at_click[j]])
                          }
                          if (success) {
                              //success_audio.play();
                          } else {
                              setTimeout(() => {
                                  //fail_audio.play();
                              }, 100);
                          }
                          animate_one(0, [dot_positions[0][display_idx], dot_positions[1][display_idx]], [dot_positions[0][display_idx+1], dot_positions[1][display_idx+1]], display_guesses, 0)
                          draw_prev_pt([dot_positions[0][display_idx], dot_positions[1][display_idx]], default_prev_pt_rad * sfd, ctx)
                          i = i + 1
                        }
                      }
                    }
                  */
              };
  
   
              // function to end trial when it is time
              const end_trial = () => {
                  // kill any remaining setTimeout handlers
                  this.jsPsych.pluginAPI.clearAllTimeouts();
                  // gather the data to store for the trial
                  var trial_data = {
                      rt: rts,
                      response_x: click_x,
                      response_y: click_y,
                      response_success: guess_success,
                      scale_at_response: scale_at_click
                  };
                  window.removeEventListener('touchmove', function(e) {
                      e.preventDefault();
                  }, {passive:false});
                  // clear the display
                  display_element.innerHTML = "";
                  window.removeEventListener("resize", update_html);
                  window.removeEventListener("orientationchange", update_html);
                  // move on to the next trial
                  this.jsPsych.finishTrial(trial_data);
              };
          }
      }
      DotTaskMultiplePlugin.info = info;
  
      return DotTaskMultiplePlugin;
  
  })(jsPsychModule);
  