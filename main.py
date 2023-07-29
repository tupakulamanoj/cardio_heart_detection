from flask import Flask,render_template,redirect,request
import joblib
import warnings
warnings.filterwarnings('ignore')

app=Flask(__name__)

@app.route('/',methods=['GET','POST'])
def hello():
    if request.method == 'POST':
        gender=request.form['gender']
        height=request.form['height']
        weight=request.form['weight']
        BP_High=request.form['bp_high']
        BP_Low=request.form['bp_low']
        Cholestrol=request.form['cholestrol']
        gluocose=request.form['gluocose']
        smoke=request.form['smoke']
        alcohol=request.form['alcohol']
        active=request.form['active']
        model=joblib.load('cardioheart')
        prediction=model.predict([[gender,height,weight,BP_High,BP_Low,Cholestrol,gluocose,smoke,alcohol,active]])
        if prediction == 1 or prediction == '1' :
            return render_template('index2.html')
        else:
            return render_template('index3.html')
        
    return render_template('index.html')




if __name__=='__main__':
    app.run(debug=True)