var jsPsychDotTask = (function (jspsych) {
  'use strict';

    const info = {
        name: "dot-task",
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
            star_idx: {
                type: jspsych.ParameterType.Int,
                pretty_name: "star_idx",
                default: -1,
            },
            progress_prompt: {
                type: jspsych.ParameterType.String,
                pretty_name: "progress_prompt",
                default: "Woohoo! Aren't you smart.",
            },
            is_practice: {
                type: jspsych.ParameterType.Bool,
                pretty_name: "practice",
                default: false,
            },
            allow_retry: {
                type: jspsych.ParameterType.Bool,
                pretty_name: "retry",
                default: false,
            },
            progress_audio: {
                type: jspsych.ParameterType.String,
                pretty_name: "progress_audio",
                default: null,
            },
            n_stars: {
                type: jspsych.ParameterType.Int,
                pretty_name: "n_stars",
                default: 8,
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
     * dot-task
     * @author Josh de Leeuw
     * @see {@link https://www.jspsych.org/plugins/jspsych-dot-task/ dot-task plugin documentation on jspsych.org}
     */
    class DotTaskPlugin {
        constructor(jsPsych) {
            this.jsPsych = jsPsych;
        }
        trial(display_element, trial) {

            var success_audio = new Audio()
            success_audio.src = 'static/sounds/success_sound.mp3'
            var fail_audio = new Audio()
            fail_audio.src = 'static/sounds/fail_sound.mp3'
            var guess_audio = new Audio()
            guess_audio.src = 'static/sounds/guess_sound.mp3'
            
            var greatjob_audio = new Audio()
            greatjob_audio.src = trial.progress_audio

            var n_to_animate = trial.n_to_animate

            var screen_fill = 0.95
            var id;
            var default_dot_rad = 8 * 8
            var default_prev_pt_rad = 20 
            var guess_rad = 50 
            var default_feedback_dot_rad = 80//75
            var default_poss_region_rad = 324 
            var default_poss_region_inner_rad = 30
            var animate_interval_time = 1200
            const scaleSpeed = 0.8; // Rate of scale increase
            const angleSpeed = 0.08//Math.PI/(((1-init_scale)/scaleSpeed)-0.5)

            var animate_end_time = 2000
            var before_feedback_time = 400
            var animate_feedback_time = 1400
            var before_move_next_time = 0
            var animate_over = false;
            var arrow_speed = 0.06

            var images = [];

            var rcanvas = ""
            var rctx = ""
            var canvas = ""
            var ctx = ""
            var canvas_cont = ""

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
                  //update_html()
                  var sfd = get_scale_from_default()
                  var dot_positions = get_display_dot_positions()
                  draw_prev_pt([dot_positions[0][dot_idx], dot_positions[1][dot_idx]], default_prev_pt_rad * sfd, ctx)
                  draw_star([dot_positions[0][dot_idx], dot_positions[1][dot_idx]], default_dot_rad * sfd, rctx)
                  animate_start() 
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

            //dimensions of current screen, based on default dimensions and scale given this persons screen size
            function get_canvas_dims() {
                var sfd = get_scale_from_default()
                return([sfd * trial.default_width, sfd * trial.default_height])
            }

            function remove_event_listeners(canvas) {
                //add click listener
                canvas.removeEventListener('mousedown', function(e) {
                    on_click(canvas, e)
                })
                window.removeEventListener('touchmove', function(e) {
                    e.preventDefault();
                }, {passive:false});
                canvas.removeEventListener('touchstart', function(e) {
                    e.preventDefault();
                    on_click(canvas, e)
                }, false)
            }

            function add_listeners(canvas) {
                //add click listener
                window.addEventListener("resize", reset_html);
                window.addEventListener("orientationchange", reset_html);
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

            
            function reset_html() {
                var [curr_w, curr_h] = get_canvas_dims()
                canvas.width = curr_w
                rcanvas.width = curr_w
                canvas_cont.width = curr_w
                canvas.height = curr_h
                rcanvas.height = curr_h
                canvas_cont.height = curr_h

                ctx.clearRect(0,0, curr_w,curr_h)
                rctx.clearRect(0,0, curr_w,curr_h)
                draw_bg(ctx, curr_w, curr_h)
                //get dot positions according to true positions, default scale, and scale from default
                var dot_positions = get_display_dot_positions()
                var sfd = get_scale_from_default()
                //draw prev pts and lines
                for(var i=0;i<=dot_idx;i++) {
                    draw_prev_pt([dot_positions[0][i], dot_positions[1][i]], default_prev_pt_rad * sfd, ctx)
                    if (i<=dot_idx-1) {
                        draw_line([dot_positions[0][i], dot_positions[1][i]], [dot_positions[0][i+1], dot_positions[1][i+1]], ctx)
                    }
                }
                draw_star([dot_positions[0][dot_idx], dot_positions[1][dot_idx]], default_dot_rad * sfd, rctx)
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
                var html = "";
                html += '<div id="cont" class="canvas-container" style="width:' + curr_w + 'px; height:' + curr_h + 'px;">' +
                        '<canvas id="rotatingCanvas" width="' + (curr_w) + '" height="' + (curr_h) + '"></canvas>' +
                        '<canvas id="staticCanvas" width="' + (curr_w) + '" height="' + curr_h + '" style="border:' + border_w + 'px solid black;"></canvas>' +
                        '</div>'
                html += '<div id="temp-div"></div>'
                display_element.innerHTML = html
                //make canvas non-selectable
                canvas_cont = document.getElementById('cont')
                canvas = document.getElementById('staticCanvas')
                ctx = canvas.getContext("2d");
                draw_bg(ctx, curr_w, curr_h)
                rcanvas = document.getElementById('rotatingCanvas');
                rctx = rcanvas.getContext('2d');
                add_listeners(rcanvas)
                prevent_highlight(rcanvas)
                prevent_highlight(canvas)
            }   

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

            
            function draw_bg_end(curr_ctx, w, h) {
                curr_ctx.clearRect(0, 0, w, h); 
                curr_ctx.drawImage(images[0], 0, 0, w, h); 
            }
            

            function fillStar(i) {  
                const stars = document.querySelectorAll(".star");
                // Fill a random star with the "active" class
                stars[i-1].classList.add("active");
                stars[i-1].style.backgroundColor = star_colors[i-1]
            }

            var star_colors = ["#F09EA7", "#F6CA94", "#FAFABE", "#C1EBC0", "#C7CAFF", "#CDABEB", "#F6C2F3", "#F09EA7"];
            function add_stars(h) {
                var padding_t = h/5
                var star_height = 100//h - padding_t
                var star_width = star_height
                // Select the container where you want to add the stars
                const starsContainer = document.createElement("div");
                starsContainer.id = "stars-container";  // Set the container's ID
                // Loop to create stars based on trial.total_stars and trial.star_idx
                for (let i = 1; i <= trial.n_stars; i++) {
                    const star = document.createElement("span");  // Create a new <span> element for each star
                    star.classList.add("star");  // Add the class "star" to the <span>
                    // Add an active class and background color if the star is "active"
                    if (i < trial.star_idx) {
                        star.classList.add("active");
                        star.style.backgroundColor = star_colors[i - 1]; // Set the star color based on the index
                    }
                    star.dataset.index = i;  // Set the data-index attribute to store the star's index
                    star.style.height = star_height + "px";
                    star.style.width = star_width + "px";
                    // Append the star to the container
                    starsContainer.appendChild(star);
                }

                starsContainer.style.paddingTop = padding_t+"px";
                // Find the parent element where you want to insert the stars container
                const temp = document.getElementById("temp-el");  // Adjust the parent container ID as needed

                // Insert the stars container after the video container
                temp.appendChild(starsContainer);
            }

            function add_button(curr_w, h, rest) {
                const canvasContainer = document.getElementById("cont");
                // Set a new height for the container
                canvasContainer.style.height = h + "px";
                const temp = document.createElement("div");  // Changed from <temp> to <div> for proper HTML element
                temp.id = "temp-el";
                temp.style.height = rest + "px";  // Set the height of the container
                temp.style.display = "flex";  // Use flexbox to align elements (button and stars)
                temp.style.flexDirection = "column";  // Stack the elements vertically
                temp.style.alignItems = "center"; 
                // Add the container after the canvas container
                canvasContainer.after(temp);
                
                const prompt = document.createElement("h3");


                if (trial.is_practice) {
                    var passed_ic = (n_correct>2)
                    if (passed_ic || (!(trial.allow_retry))) {
                        trial.progress_prompt = "Good job! Now, you'll get to try some different patterns!"
                    } else {
                        trial.progress_prompt = "Good job! Let's practice one more time!"
                    }
                }

                prompt.textContent = trial.progress_prompt
                temp.appendChild(prompt);
                
                add_stars()

                // add button
                const button = document.createElement("button");
                button.id = "next-button";
                button.textContent = "Next"; // Set the button text
                var button_space = rest * 0.3
                var x = button_space/6 //6x
                //button.style.marginTop = x + "px";
                button.style.fontSize = (2*x) + "px";  // Make the text bigger
                button.style.padding = (0.5*x)+"px";  // Increase padding (height and width)
                button.style.fontWeight = "bold";  // Make the text bold
                button.style.borderRadius = "8px"; 
                button.style.maxWidth = "100px";
                temp.appendChild(button);
                
                var star_space = rest * 0.7

                if (trial.star_idx <= trial.n_stars) {
                    setTimeout(() => {
                        if (trial.star_idx > 0) {
                            fillStar(trial.star_idx)
                        }
                    }, 500);
                }
                setTimeout(() => {
                    button.addEventListener("click", () => {
                        end_trial()
                    });
                }, 700);

            }

            function animate_end() {
                window.removeEventListener("resize", reset_html);
                window.removeEventListener("orientationchange", reset_html);
                var o = 0.05
                animate_over = false
                var [curr_w, curr_h] = get_canvas_dims()
                var h = curr_h*(3/5)
                //canvas.height = h
                rcanvas.height = h
                var id = setInterval(animate_next, 50);
                //var [curr_w, curr_h] = get_canvas_dims()
                setTimeout(() => {
                    greatjob_audio.play();
                }, 500);
                function animate_next() {
                    if (o>0.9) {
                        add_button(curr_w, h, curr_h-h)
                        rctx.globalAlpha = 1
                        ctx.clearRect(0, 0, curr_w, curr_h);
                        canvas.height = h
                        clearInterval(id);
                        animate_over = true
                    } else {
                        ctx.globalAlpha = 1-o
                        draw_bg_end(ctx, curr_w, curr_h)
                        //draw_bg_end(rctx, curr_w, h)
                        rctx.globalAlpha = o
                        draw_star([curr_w/2, h/2], h, rctx)
                        o = o * 1.1
                    }
                }
            }

            //static html at curr point
            //simply clear animation screen and draw star on it
            function update_html() {
                var dot_positions = get_display_dot_positions()
                var sfd = get_scale_from_default()
                draw_prev_pt([dot_positions[0][dot_idx], dot_positions[1][dot_idx]], default_prev_pt_rad * sfd, ctx)
                rctx.clearRect(0, 0, rcanvas.width, rcanvas.height);
                draw_star([dot_positions[0][dot_idx], dot_positions[1][dot_idx]], default_dot_rad * sfd, rctx)
            } 
                    
            function animate_start() {
                var n_animated = 0
                animate_over = false
                id = setInterval(animate_next, animate_interval_time);
                function animate_next() {
                  if (n_animated==n_to_animate) {
                    clearInterval(id);
                    animate_over = true;
                    reset_html()
                    guess_audio.play();
                    ignore_click=false;
                    start_time = performance.now();
                  } else {
                    var sfd = get_scale_from_default()
                    var scale = trial.default_scale * sfd
                    scale_at_click[dot_idx+1] = scale
                    var dot_positions = get_display_dot_positions()
                    animate_one(0, [dot_positions[0][dot_idx], dot_positions[1][dot_idx]], [dot_positions[0][dot_idx+1], dot_positions[1][dot_idx+1]], null, 0)
                    dot_idx = dot_idx + 1
                    //give 200ms to update html
                    setTimeout(() => {
                        draw_prev_pt([dot_positions[0][dot_idx], dot_positions[1][dot_idx]], default_prev_pt_rad * sfd, ctx)
                    }, animate_interval_time-200);
                    n_animated = n_animated + 1
                  }
                }
            }


            function spin_star(x, y, curr_angle, curr_rad, min_rad, max_rad, inc) {
                curr_rad = Math.max(Math.min(curr_rad, max_rad), min_rad)
                // Clear the canvas
                rctx.clearRect(0, 0, rotatingCanvas.width, rotatingCanvas.height);
                // Save the current canvas state
                rctx.save();
                // Translate the canvas to the center of the canvas
                rctx.translate(x, y);
                //Rotate the canvas by the angle (in radians)
                rctx.rotate(curr_angle);
                rctx.translate(-x, -y);
                //draw star
                draw_star([x, y], curr_rad, rctx);

                // Restore the canvas state
                rctx.restore();
                // Update the angle for rotation
                curr_angle += angleSpeed;
                // Increase the scale
                // Request animation frame to create a smooth animation loop

                //if increasing, keep going or change to dec if at max_rad
                if (inc) {
                    curr_rad += scaleSpeed;
                    if (curr_rad < max_rad) {
                        requestAnimationFrame(function() {
                            spin_star(x, y, curr_angle, curr_rad, min_rad, max_rad, inc);
                        });
                    } else {
                        requestAnimationFrame(function() {
                            spin_star(x, y, curr_angle, curr_rad, min_rad, max_rad, false);
                        });
                    }
                } else {
                    curr_rad -= scaleSpeed;
                    if (curr_rad > min_rad) {
                        requestAnimationFrame(function() {
                            spin_star(x, y, curr_angle, curr_rad, min_rad, max_rad, inc);
                        });
                    }
                }
            }

            function animate_success(guess, star_loc) {
                //rotate and grow star
                //play sound
                var sfd = get_scale_from_default()
                var min_rad = sfd*default_dot_rad
                var max_rad = sfd*default_dot_rad*1.5
                var curr_rad = min_rad
                spin_star(star_loc[0], star_loc[1], 0, curr_rad, min_rad, max_rad, true)
            }

            //animate star shooting to next point
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
                if (progress>=1) {
                    draw_star(loc,  sfd * default_dot_rad, rctx)
                  } else {
                    draw_star(curr_loc,  sfd * default_dot_rad, rctx)
                  }
                if (progress < 1) {
                    //request the next animation frame
                    requestAnimationFrame(animate_one.bind(null, progress + arrow_speed, prev_loc, loc, guesses, n_calls+1));
                } else {

                }
            }

            function draw_line(prev_loc, loc, curr_ctx) {
                curr_ctx.beginPath();
                curr_ctx.strokeStyle = "rgb(255,230,0)";
                ctx.setLineDash([1, 1]);
                curr_ctx.moveTo(prev_loc[0], prev_loc[1]);
                curr_ctx.lineTo(loc[0], loc[1]);
                curr_ctx.stroke();
            }

            function draw_bg(curr_ctx, w, h) {
                curr_ctx.drawImage(images[0], 0, 0, w, h);
            }
            
            function draw_guess(loc, rad, curr_ctx) {
                curr_ctx.globalAlpha = 0.3
                curr_ctx.fillStyle = "pink";
                curr_ctx.beginPath();
                curr_ctx.arc(loc[0], loc[1], rad/2, 0, 2*Math.PI);
                curr_ctx.fill();
                curr_ctx.globalAlpha = 1
                curr_ctx.drawImage(images[1],  loc[0]-(rad/2), loc[1]-(rad/2), rad, rad);
            }

            function draw_star(loc, rad, curr_ctx) {
                curr_ctx.drawImage(images[4],  loc[0]-(rad/2), loc[1]-(rad/2), rad, rad);
            }

            function draw_prev_pt(loc, rad, curr_ctx) {
                curr_ctx.drawImage(images[3],  loc[0]-(rad/2), loc[1]-(rad/2), rad, rad);
            }

            function draw_dot(loc, rad, curr_ctx) {
                curr_ctx.fillStyle = "rgb(255,230,0)";
                curr_ctx.beginPath();
                curr_ctx.arc(loc[0], loc[1], rad, 0, 2*Math.PI);
                curr_ctx.fill();
            }


            // initialize vars
            var start_time = performance.now();
            var scale_at_click = []
            var click_x = [];
            var click_y = [];
            var guess_success = [];
            var n_correct = 0;
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
                    rts[dot_idx+1] = end_time - start_time;

                    //record click, scaled down in terms of true x/y coords
                    var scale = trial.default_scale * sfd
                    var shift_x = trial.default_shift[0]
                    var shift_y = trial.default_shift[1]
                    click_x[dot_idx+1] = (x/scale)-shift_x
                    click_y[dot_idx+1] = (y/scale)-shift_y
                    scale_at_click[dot_idx+1] = scale
                    //check success
                    var success = check_success(x, y, dot_positions, sfd)
                    guess_success[dot_idx+1] = success
                    if (success) {
                        n_correct = n_correct + 1
                    }
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
                //show guess at click pos
                var [curr_w,curr_h] = get_canvas_dims()
                var sfd = get_scale_from_default()
                var dot_positions = get_display_dot_positions()
                draw_guess([x, y], guess_rad*sfd, rctx)
                var display_guesses = []
                display_guesses.push([x, y])
                //star moves to next loc
                setTimeout(() => {
                    animate_one(0, [dot_positions[0][dot_idx], dot_positions[1][dot_idx]], [dot_positions[0][dot_idx+1], dot_positions[1][dot_idx+1]], display_guesses, 0)
                }, before_move_next_time)
                //start audio a bit early 
                setTimeout(() => {
                    if (success) {
                        success_audio.play();
                    } else {
                        fail_audio.play()
                    }
                }, before_feedback_time - 100);
                setTimeout(() => {
                    if (success) {
                        //keep guess and star, but make spin
                        animate_success(display_guesses[0], [dot_positions[0][dot_idx+1], dot_positions[1][dot_idx+1]])
                    } else {
                        setTimeout(() => {
                            //remove guess
                            rctx.clearRect(0,0,curr_w,curr_h)
                            draw_star([dot_positions[0][dot_idx+1], dot_positions[1][dot_idx+1]], default_dot_rad * sfd, rctx)
                        }, animate_feedback_time - 100)
                    }
                    setTimeout(() => {                        
                        if (dot_idx >= trial.dot_positions[0].length-2) {
                            animate_end()
                            // setTimeout(() => {
                            //     end_trial()
                            // }, animate_end_time);
                        } else {
                            dot_idx = dot_idx + 1
                            draw_prev_pt([dot_positions[0][dot_idx], dot_positions[1][dot_idx]], default_prev_pt_rad * sfd, ctx)
                            reset_html()
                            ignore_click=false;
                            start_time = performance.now();
                        }
                    }, animate_feedback_time);
                }, before_feedback_time);
            };
 
            // function to end trial when it is time
            const end_trial = () => {
                // kill any remaining setTimeout handlers
                this.jsPsych.pluginAPI.clearAllTimeouts();
                // gather the data to store for the trial
                //remove listeners
                remove_event_listeners(rcanvas)
                // clear the display
                var trial_data = {
                    rt: rts,
                    response_x: click_x,
                    response_y: click_y,
                    response_success: guess_success,
                    scale_at_response: scale_at_click
                };
                display_element.innerHTML = "";
                // move on to the next trial
                this.jsPsych.finishTrial(trial_data);
            };
        }
    }
    DotTaskPlugin.info = info;

    return DotTaskPlugin;

})(jsPsychModule);
